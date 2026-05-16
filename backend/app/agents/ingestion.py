"""Ingestion Agent — source normalisation and filtering (FR-1.1 to FR-1.5).

Phase 1: Stub that passes sources through with basic filtering.
Phase 2: Real implementation with Gemini-powered content extraction.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from app.agents.base import BaseAgent
from app.config import settings
from app.schemas import SourceDocument


class IngestionAgent(BaseAgent):
    name = "ingestion"

    async def run(self, input_data: list[SourceDocument]) -> list[SourceDocument]:
        """Filter and normalise source documents."""
        await self.emit_event(
            "agent_start",
            input_summary=f"Received {len(input_data)} source documents",
        )

        accepted: list[SourceDocument] = []
        seen_hashes: set[str] = set()

        for doc in input_data:
            # FR-1.3 — staleness filter
            if doc.recency_days > settings.STALENESS_THRESHOLD_DAYS:
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {doc.filename}",
                    output_summary=f"Rejected: stale ({doc.recency_days:.0f} days old, threshold={settings.STALENESS_THRESHOLD_DAYS})",
                    detail={"filename": doc.filename, "reason": "stale", "recency_days": doc.recency_days},
                )
                continue

            # FR-1.4 — duplicate filter
            if doc.content_hash in seen_hashes:
                await self.emit_event(
                    "filtered_out",
                    input_summary=f"Source {doc.filename}",
                    output_summary=f"Rejected: duplicate (hash={doc.content_hash})",
                    detail={"filename": doc.filename, "reason": "duplicate"},
                )
                continue

            seen_hashes.add(doc.content_hash)
            accepted.append(doc)

            await self.emit_event(
                "source_accepted",
                input_summary=f"Source {doc.filename} ({doc.kind.value})",
                output_summary=f"Accepted with credibility={doc.credibility_prior:.2f}",
                detail={
                    "filename": doc.filename,
                    "kind": doc.kind.value,
                    "credibility": doc.credibility_prior,
                },
            )

        await self.emit_event(
            "agent_end",
            input_summary=f"{len(input_data)} sources received",
            output_summary=f"{len(accepted)} sources accepted, {len(input_data) - len(accepted)} filtered out",
        )

        return accepted
