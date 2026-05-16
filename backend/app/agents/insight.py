"""Insight Agent — signal extraction and contradiction resolution (FR-2.1 to FR-2.6).

Phase 1: Stub returning hard-coded signals for demo.
Phase 2: Real Gemini-powered extraction + contradiction resolution.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from app.agents.base import BaseAgent
from app.schemas import (
    ConflictReport, ResolvedSignal, Signal, SignalKind, SourceDocument,
)


class InsightAgent(BaseAgent):
    name = "insight"

    async def run(self, input_data: list[SourceDocument]) -> dict:
        """Extract signals and resolve contradictions."""
        await self.emit_event(
            "agent_start",
            input_summary=f"Analyzing {len(input_data)} accepted sources",
        )

        # Phase 1 — stub signals
        signals = self._stub_extract_signals(input_data)

        await self.emit_event(
            "signals_extracted",
            output_summary=f"Extracted {len(signals)} signals",
            detail=[s.model_dump(mode='json') for s in signals],
        )

        # Phase 1 — stub contradiction resolution
        resolved, conflicts = self._stub_resolve(signals)

        for conflict in conflicts:
            await self.emit_event(
                "conflict_resolved",
                output_summary=f"Conflict on {conflict.metric}: chose signal {conflict.winning_signal_id}",
                detail=conflict.model_dump(mode='json'),
            )

        await self.emit_event(
            "agent_end",
            output_summary=f"{len(resolved)} resolved signals, {len(conflicts)} conflicts resolved",
        )

        return {"resolved_signals": resolved, "conflict_reports": conflicts}

    # ── Phase 1 stubs ────────────────────────────────────────────────────────

    def _stub_extract_signals(self, docs: list[SourceDocument]) -> list[Signal]:
        """Return hard-coded demo signals."""
        doc_ids = [d.id for d in docs]
        now = datetime.utcnow()
        return [
            Signal(
                kind=SignalKind.STOCK_LEVEL, sku="AC-INV-12K-HAI",
                metric="inventory_units", value=18, delta_vs_baseline_pct=-40.0,
                source_doc_ids=doc_ids[:1], extracted_at=now,
            ),
            Signal(
                kind=SignalKind.STOCK_LEVEL, sku="AC-INV-12K-HAI",
                metric="inventory_units", value=42, delta_vs_baseline_pct=0.0,
                source_doc_ids=doc_ids[1:2] if len(doc_ids) > 1 else doc_ids[:1],
                extracted_at=now,
            ),
            Signal(
                kind=SignalKind.SALES_CHANGE, sku="AC-INV-12K-HAI",
                metric="weekly_sales_velocity", value=35, delta_vs_baseline_pct=45.0,
                source_doc_ids=doc_ids[1:2] if len(doc_ids) > 1 else doc_ids[:1],
                extracted_at=now,
            ),
            Signal(
                kind=SignalKind.SUPPLIER_STATUS, sku=None,
                metric="supplier_delay_days", value=10, delta_vs_baseline_pct=None,
                source_doc_ids=doc_ids[2:3] if len(doc_ids) > 2 else doc_ids[:1],
                extracted_at=now,
            ),
            Signal(
                kind=SignalKind.COMPLAINT_CLUSTER, sku="AC-INV-12K-HAI",
                metric="complaint_count_7d", value=12, delta_vs_baseline_pct=200.0,
                source_doc_ids=doc_ids[3:4] if len(doc_ids) > 3 else doc_ids[:1],
                extracted_at=now,
            ),
            Signal(
                kind=SignalKind.EXTERNAL_SHOCK, sku=None,
                metric="fuel_price_increase_pct", value=15, delta_vs_baseline_pct=15.0,
                source_doc_ids=doc_ids[4:5] if len(doc_ids) > 4 else doc_ids[:1],
                extracted_at=now,
            ),
        ]

    def _stub_resolve(
        self, signals: list[Signal]
    ) -> tuple[list[ResolvedSignal], list[ConflictReport]]:
        """Stub — all signals pass through with high confidence, one demo conflict."""
        resolved = []
        conflicts = []

        for s in signals:
            resolved.append(ResolvedSignal(
                **s.model_dump(mode='json'),
                confidence=0.85,
                resolution_reason="Single source — no contradiction",
            ))

        # Simulate one conflict for demo
        if len(resolved) >= 2:
            conflicts.append(ConflictReport(
                metric="inventory_units",
                sku="AC-INV-12K-HAI",
                conflicting_signal_ids=[resolved[0].id, resolved[1].id],
                winning_signal_id=resolved[0].id,
                resolution_reason="Warehouse CSV (credibility=0.85) preferred over sales dashboard (credibility=0.80)",
                confidence=0.82,
            ))

        return resolved, conflicts
