"""Planner Agent — action chain generation with constraint checking (FR-3.1 to FR-3.7).

Phase 1: Stub returning a hard-coded 4-action DAG.
Phase 2: Real Gemini-powered planning with constraint enforcement.
"""

from __future__ import annotations

from typing import Any

from app.agents.base import BaseAgent
from app.schemas import (
    Action, ActionKind, ActionPlan, ResolvedSignal, Urgency,
)


class PlannerAgent(BaseAgent):
    name = "planner"

    async def run(self, input_data: dict) -> ActionPlan:
        """Generate a constrained action plan from resolved signals."""
        signals: list[ResolvedSignal] = input_data.get("resolved_signals", [])
        conflicts = input_data.get("conflict_reports", [])

        await self.emit_event(
            "agent_start",
            input_summary=f"Planning from {len(signals)} resolved signals, {len(conflicts)} conflicts",
        )

        # Phase 1 — stub action chain
        plan = self._stub_plan(signals)

        await self.emit_event(
            "plan_generated",
            output_summary=f"Generated {len(plan.actions)} actions, executable={plan.is_executable}",
            detail=plan.model_dump(mode='json'),
        )

        await self.emit_event(
            "agent_end",
            output_summary=f"Action plan with {len(plan.actions)} steps, impact ≈ PKR {plan.total_estimated_impact_pkr:,.0f}",
        )

        return plan

    # ── Phase 1 stub ─────────────────────────────────────────────────────────

    def _stub_plan(self, signals: list[ResolvedSignal]) -> ActionPlan:
        """Hard-coded 4-action DAG for demo."""
        a1 = Action(
            id="act-1",
            kind=ActionKind.VALIDATE,
            params={"sku": "SKU-AC-001", "check": "current_stock_vs_reported"},
            depends_on=[],
            constraints_required=["lead_time"],
            rationale="Validate actual warehouse stock against reported 120 units before ordering — prevents over-ordering from stale data.",
            estimated_impact_pkr=0,
            customers_affected=0,
            urgency=Urgency.HIGH,
        )
        a2 = Action(
            id="act-2",
            kind=ActionKind.ORDER,
            params={"sku": "SKU-AC-001", "quantity": 200, "supplier": "Lahore Electronics Hub"},
            depends_on=["act-1"],
            constraints_required=["budget", "lead_time"],
            rationale="Emergency reorder of 200 AC units from backup supplier to cover projected 3-week demand spike.",
            estimated_impact_pkr=1_800_000,
            customers_affected=45,
            urgency=Urgency.CRITICAL,
        )
        a3 = Action(
            id="act-3",
            kind=ActionKind.NOTIFY,
            params={
                "recipients": ["logistics-team", "customer-service"],
                "message": "AC stock critically low. Emergency order placed. Customer ETAs may shift.",
            },
            depends_on=["act-2"],
            constraints_required=[],
            rationale="Proactive notification to logistics and CS teams to prepare for incoming shipment and manage customer expectations.",
            estimated_impact_pkr=0,
            customers_affected=45,
            urgency=Urgency.HIGH,
        )
        a4 = Action(
            id="act-4",
            kind=ActionKind.SCHEDULE_MONITOR,
            params={"sku": "SKU-AC-001", "interval_hours": 24, "duration_days": 7},
            depends_on=["act-2"],
            constraints_required=["rate_limit"],
            rationale="Monitor AC stock levels daily for the next 7 days to detect if the emergency order resolves the stockout risk.",
            estimated_impact_pkr=0,
            customers_affected=0,
            urgency=Urgency.MEDIUM,
        )

        return ActionPlan(
            actions=[a1, a2, a3, a4],
            total_estimated_impact_pkr=1_800_000,
            constraint_violations=[],
            is_executable=True,
        )
