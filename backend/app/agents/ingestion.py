"""Ingestion Agent — source normalisation and filtering (FR-1.1 to FR-1.5).

Phase 2: Real file parsing from scenario directories with config.yaml-driven source lists.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import pathlib
from datetime import datetime
from typing import Any

import email as _email
from bs4 import BeautifulSoup as _BS

import yaml

from app.agents.base import BaseAgent
from app.config import settings
from app.schemas import SourceDocument, SourceKind

PROJECT_ROOT = pathlib.Path(__file__).parent.parent.parent.parent

_KIND_MAP = {
    "csv": SourceKind.CSV,
    "json": SourceKind.JSON,
    "email": SourceKind.EMAIL,
    "news_html": SourceKind.NEWS_HTML,
    "news_mhtml": SourceKind.NEWS_MHTML,
    "pdf": SourceKind.PDF,
}


def parse_mhtml(filepath):
    with open(filepath, "rb") as f:
        msg = _email.message_from_bytes(f.read())
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            raw = part.get_payload(decode=True)
            charset = part.get_content_charset() or "utf-8"
            html = raw.decode(charset, errors="replace")
            return _BS(html, "html.parser").get_text(
                separator="\n", strip=True)[:6000]
    return ""


def _parse_file(filepath: pathlib.Path) -> str | dict | list:
    """Read and parse a source file by extension."""
    ext = filepath.suffix.lower()
    if ext == ".csv":
        text = filepath.read_text(encoding="utf-8")
        reader = csv.DictReader(io.StringIO(text))
        return [row for row in reader]
    elif ext == ".json":
        with open(filepath, encoding="utf-8") as f:
            return json.load(f)
    elif ext == ".txt":
        return filepath.read_text(encoding="utf-8")
    elif ext == ".html":
        text = filepath.read_text(encoding="utf-8")
        return _BS(text, "html.parser").get_text(separator="\n", strip=True)[:6000]
    elif ext == ".mhtml":
        return parse_mhtml(str(filepath))
    else:
        return filepath.read_text(encoding="utf-8")


def _content_hash(content: str) -> str:
    return hashlib.md5(content[:2000].encode()).hexdigest()[:16]


class IngestionAgent(BaseAgent):
    name = "ingestion"

    async def run(self, input_data: Any) -> list[SourceDocument]:
        """Load, parse, filter and normalise source documents from scenario files."""
        # input_data is the scenario_id string
        scenario_id = input_data if isinstance(input_data, str) else str(input_data)
        scenario_dir = PROJECT_ROOT / "scenarios" / scenario_id

        await self.emit_event(
            "agent_start",
            input_summary=f"Loading sources for scenario {scenario_id} from {scenario_dir}",
        )

        # Load config.yaml for the source list
        config_path = scenario_dir / "config.yaml"
        if not config_path.exists():
            await self.emit_event("agent_end", output_summary="No config.yaml found — 0 sources loaded")
            return []

        with open(config_path, encoding="utf-8") as f:
            config = yaml.safe_load(f)

        source_entries = config.get("sources", [])
        accepted: list[SourceDocument] = []
        seen_hashes: set[str] = set()

        for entry in source_entries:
            filename = entry.get("file", "")
            kind_str = entry.get("kind", "")
            credibility_prior = float(entry.get("credibility_prior", 0.5))

            filepath = scenario_dir / filename
            if not filepath.exists():
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {filename}",
                    output_summary=f"Rejected: file not found at {filepath}",
                    detail={"file": filename, "reason": "file_not_found"},
                )
                continue

            # Parse content
            try:
                content = _parse_file(filepath)
            except Exception as e:
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {filename}",
                    output_summary=f"Rejected: parse error — {e}",
                    detail={"file": filename, "reason": "parse_error", "error": str(e)},
                )
                continue

            # Calculate recency: prefer config-specified value for determinism (A8 fix)
            config_recency = entry.get("recency_days")
            if config_recency is not None:
                recency_days = float(config_recency)
            else:
                mtime = os.path.getmtime(filepath)
                recency_days = (datetime.now().timestamp() - mtime) / 86400

            # Staleness check
            if recency_days > settings.STALENESS_THRESHOLD_DAYS:
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {filename}",
                    output_summary=f"Rejected: stale ({recency_days:.0f} days old, threshold={settings.STALENESS_THRESHOLD_DAYS})",
                    detail={"file": filename, "reason": "stale", "recency_days": round(recency_days, 1)},
                )
                continue

            # Duplicate check via MD5
            content_str = json.dumps(content, default=str) if isinstance(content, (dict, list)) else str(content)
            c_hash = _content_hash(content_str)

            if c_hash in seen_hashes:
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {filename}",
                    output_summary=f"Rejected: duplicate (hash={c_hash})",
                    detail={"file": filename, "reason": "duplicate"},
                )
                continue

            seen_hashes.add(c_hash)

            # Map kind string to SourceKind enum
            kind = _KIND_MAP.get(kind_str, SourceKind.EMAIL)

            doc = SourceDocument(
                kind=kind,
                fetched_at=datetime.utcnow(),
                content=content,
                credibility_prior=credibility_prior,
                recency_days=round(recency_days, 1),
                filename=filename,
                content_hash=c_hash,
            )
            accepted.append(doc)

            await self.emit_event(
                "source_accepted",
                input_summary=f"Source {filename} ({kind.value})",
                output_summary=f"Accepted with credibility={credibility_prior:.2f}",
                detail={
                    "file": filename,
                    "kind": kind.value,
                    "credibility_prior": credibility_prior,
                    "recency_days": round(recency_days, 1),
                    "content_length": len(content_str),
                },
            )

        await self.emit_event(
            "agent_end",
            input_summary=f"{len(source_entries)} sources listed in config.yaml",
            output_summary=f"{len(accepted)} sources accepted, {len(source_entries) - len(accepted)} filtered out",
        )

        return accepted
