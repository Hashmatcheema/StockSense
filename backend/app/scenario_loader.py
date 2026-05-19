"""Scenario loader — loads fixture files from /scenarios/{id}/ (SRS §3.2)."""

from __future__ import annotations

import csv
import json
import hashlib
import io
from datetime import datetime
from pathlib import Path

from app.config import settings
from app.schemas import (
    BusinessState, ScenarioInfo, SourceDocument, SourceKind,
)


# ── Credibility priors per source type (FR-1.5) ─────────────────────────────

_CREDIBILITY_PRIORS: dict[SourceKind, float] = {
    SourceKind.CSV: 0.85,
    SourceKind.JSON: 0.80,
    SourceKind.EMAIL: 0.65,
    SourceKind.NEWS_HTML: 0.45,
    SourceKind.NEWS_MHTML: 0.70,
    SourceKind.PDF: 0.75,
}

# ── Extension → SourceKind mapping ──────────────────────────────────────────

_EXT_MAP: dict[str, SourceKind] = {
    ".csv": SourceKind.CSV,
    ".json": SourceKind.JSON,
    ".txt": SourceKind.EMAIL,
    ".html": SourceKind.NEWS_HTML,
    ".mhtml": SourceKind.NEWS_MHTML,
    ".pdf": SourceKind.PDF,
}


def _content_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def _parse_file(path: Path) -> str | dict | list:
    """Read and parse a source file into native Python structures."""
    text = path.read_text(encoding="utf-8")
    ext = path.suffix.lower()

    if ext == ".json":
        return json.loads(text)
    elif ext == ".csv":
        reader = csv.DictReader(io.StringIO(text))
        return [row for row in reader]
    elif ext == ".mhtml":
        from app.agents.ingestion import parse_mhtml
        return parse_mhtml(str(path))
    else:
        # .txt, .html, .pdf (text-mode) — return raw string
        return text


# ── Public API ───────────────────────────────────────────────────────────────

def list_scenarios() -> list[ScenarioInfo]:
    """Return metadata for all available scenarios."""
    base = Path(settings.SCENARIOS_DIR)
    scenarios = []
    for d in sorted(base.iterdir()):
        if not d.is_dir():
            continue
        config_path = d / "config.yaml"
        # Quick metadata from directory name
        sid = d.name
        # Count source files (exclude config, initial_state, .gitkeep)
        source_files = [
            f for f in d.iterdir()
            if f.is_file() and f.suffix in _EXT_MAP
        ]
        meta = _SCENARIO_META.get(sid, {})
        scenarios.append(ScenarioInfo(
            id=sid,
            title=meta.get("title", f"Scenario {sid}"),
            description=meta.get("description", ""),
            source_count=len(source_files),
            tags=meta.get("tags", []),
        ))
    return scenarios


def load_sources(scenario_id: str) -> list[SourceDocument]:
    """Load and normalise all source files for a scenario (FR-1.1, FR-1.2)."""
    base = Path(settings.SCENARIOS_DIR) / scenario_id
    if not base.exists():
        raise FileNotFoundError(f"Scenario {scenario_id} not found at {base}")

    docs = []
    for f in sorted(base.iterdir()):
        if not f.is_file() or f.suffix.lower() not in _EXT_MAP:
            continue

        kind = _EXT_MAP[f.suffix.lower()]
        content = _parse_file(f)
        content_str = json.dumps(content) if isinstance(content, (dict, list)) else str(content)

        doc = SourceDocument(
            kind=kind,
            fetched_at=datetime.utcnow(),
            content=content,
            credibility_prior=_CREDIBILITY_PRIORS[kind],
            recency_days=2.0,  # will be overridden by real data in Phase 2
            filename=f.name,
            content_hash=_content_hash(content_str),
        )
        docs.append(doc)

    return docs


def load_initial_state(scenario_id: str) -> BusinessState:
    """Load the pre-run business state for a scenario."""
    path = Path(settings.SCENARIOS_DIR) / scenario_id / "initial_state.json"
    if not path.exists():
        # Return a default state
        return _default_business_state()
    with open(path) as f:
        return BusinessState(**json.load(f))


def _default_business_state() -> BusinessState:
    """Default Khan Traders state when no fixture is available."""
    from app.schemas import RiskMetrics
    return BusinessState(
        inventory={
            "SKU-AC-001": 120,
            "SKU-WM-002": 45,
            "SKU-RF-003": 200,
            "SKU-TV-004": 30,
            "SKU-MW-005": 85,
        },
        customer_etas={
            "ORD-1001": "2026-05-20",
            "ORD-1002": "2026-05-22",
            "ORD-1003": "2026-05-18",
        },
        supplier_status={
            "Karachi Cool Systems": "active",
            "Lahore Electronics Hub": "active",
            "Faisalabad Parts Co": "active",
        },
        notification_queue=[],
        open_orders=[],
        risk_metrics=RiskMetrics(
            stockout_risk_pct=65.0,
            revenue_at_risk_pkr=3_200_000.0,
        ),
    )


# ── Scenario metadata ───────────────────────────────────────────────────────

_SCENARIO_META: dict[str, dict] = {
    "S1": {
        "title": "Supply Chain Disruption — Happy Path",
        "description": "Khan Traders faces a potential stockout on air conditioners "
                       "during peak summer season. Multiple sources report supplier delays, "
                       "rising fuel costs, and increasing customer complaints. The system must "
                       "ingest all five sources, extract insights, resolve one contradiction, "
                       "and generate a 3–5 action chain that reduces stockout risk.",
        "tags": ["happy-path", "stockout", "supply-chain"],
    },
    "S2": {
        "title": "Conflicting Market Intelligence",
        "description": "Three sources report wildly different stock levels for the same SKU. "
                       "A low-credibility news source attempts to spoof a supply crisis. "
                       "The system must identify and resolve all contradictions, rejecting "
                       "the unreliable source, and still produce a coherent action plan.",
        "tags": ["contradictions", "credibility", "filtering"],
    },
    "S3": {
        "title": "Order Failure & Automated Recovery",
        "description": "A critical reorder action fails when the supplier API times out. "
                       "The system must retry, attempt a substitution if retry fails, and "
                       "roll back dependent actions that are no longer valid.",
        "tags": ["failure", "recovery", "rollback"],
    },
}
