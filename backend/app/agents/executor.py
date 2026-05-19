"""Executor Agent — action simulation with retry, substitution, rollback (FR-4.1 to FR-4.6)."""

from __future__ import annotations

import time
from datetime import datetime, timedelta
from uuid import uuid4

from app.agents.base import BaseAgent
from app.sandbox import Sandbox
from app.schemas import Action, ActionKind, ActionPlan, ExecutionResult, ExecutionStatus


class ExecutorAgent(BaseAgent):
    name = "executor"

    def __init__(self, run_id: str, sandbox: Sandbox, scenario_id: str = "") -> None:
        super().__init__(run_id)
        self.sandbox = sandbox
        self.scenario_id = scenario_id
        self._s3_retry_done = False
        self._orders_executed = 0

    async def run(self, input_data: ActionPlan) -> list[ExecutionResult]:
        await self.emit_event("agent_start",
            input_summary=f"Executing {len(input_data.actions)} actions against sandbox")
        self.sandbox.take_snapshot()

        results: list[ExecutionResult] = []
        n_success = 0
        n_retried = 0
        n_rolled_back = 0

        for action in self._topo_sort(input_data.actions):
            result = await self._exec(action)
            results.append(result)

            if result.status == ExecutionStatus.SUCCESS:
                n_success += 1
            elif result.status == ExecutionStatus.RETRIED:
                n_retried += 1
            elif result.status == ExecutionStatus.ROLLED_BACK:
                n_rolled_back += 1

            await self.emit_event("action_executed",
                input_summary=f"{action.id} ({action.kind.value})",
                output_summary=f"Status: {result.status.value}",
                latency_ms=result.latency_ms,
                detail={
                    "action_id": action.id,
                    "action_kind": action.kind.value,
                    "status": result.status.value,
                    "state_diff": result.state_diff,
                    "latency_ms": result.latency_ms,
                    "tokens_used": 0,
                    "error": result.error,
                })

        # Final state summary
        final_risk = {
            "stockout_risk_pct": self.sandbox.state.risk_metrics.stockout_risk_pct,
            "revenue_at_risk_pkr": self.sandbox.state.risk_metrics.revenue_at_risk_pkr,
        }

        await self.emit_event("agent_end",
            output_summary=f"{n_success}/{len(results)} succeeded, {n_retried} retried, {n_rolled_back} rolled back",
            detail={
                "actions_total": len(results),
                "actions_succeeded": n_success,
                "actions_retried": n_retried,
                "actions_rolled_back": n_rolled_back,
                "final_state_summary": final_risk,
            })

        return results

    async def _exec(self, action: Action) -> ExecutionResult:
        start = time.time()
        kind = action.kind

        if kind == ActionKind.VALIDATE:
            return self._exec_validate(action, start)

        elif kind == ActionKind.NOTIFY:
            return self._exec_notify(action, start)

        elif kind == ActionKind.ORDER:
            return await self._exec_order(action, start)

        elif kind == ActionKind.ADJUST_ETA:
            return self._exec_adjust_eta(action, start)

        elif kind == ActionKind.SCHEDULE_MONITOR:
            return self._exec_schedule_monitor(action, start)

        elif kind == ActionKind.INVESTIGATE:
            return self._exec_investigate(action, start)

        elif kind == ActionKind.ROLLBACK:
            return self._exec_rollback(action, start)

        else:
            return ExecutionResult(
                action_id=action.id,
                status=ExecutionStatus.SUCCESS,
                state_diff={},
                latency_ms=int((time.time() - start) * 1000),
                tokens_used=0,
            )

    def _exec_validate(self, action: Action, start: float) -> ExecutionResult:
        sku = action.params.get("sku", "")
        diff = {"validated_skus": [sku]}
        self.sandbox.apply_diff(diff)
        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.SUCCESS,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _exec_notify(self, action: Action, start: float) -> ExecutionResult:
        notification = {
            "to": action.params.get("recipients", ["procurement-team"]),
            "message": action.rationale or action.params.get("message", ""),
            "sent": True,
            "timestamp": datetime.utcnow().isoformat(),
        }
        diff = {
            "notification_queue": [notification],
            "risk_metrics": {"pending_customer_orders_affected": -3},
        }
        self.sandbox.apply_diff(diff)
        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.SUCCESS,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    async def _exec_order(self, action: Action, start: float) -> ExecutionResult:
        sku = action.params.get("sku", "AC-INV-12K-HAI")
        qty = int(action.params.get("quantity", action.params.get("qty", 22)))
        supplier = action.params.get("supplier", "Lahore Electronics Hub")
        cost = int(action.estimated_impact_pkr) if action.estimated_impact_pkr else 0

        # S3 failure simulation
        if self.scenario_id == "S3" and not self._s3_retry_done:
            self._s3_retry_done = True
            error_msg = "Supplier API timeout: connection refused after 30s"

            await self.emit_event("action_failed",
                input_summary=f"{action.id} ({action.kind.value})",
                output_summary=f"FAILED: {error_msg}",
                detail={"action_id": action.id, "error": error_msg})

            await self.emit_event("action_retried",
                input_summary=f"{action.id} ({action.kind.value})",
                output_summary="Retrying order after supplier timeout...")

            # Retry succeeds — fall through to normal execution below
            status = ExecutionStatus.RETRIED
        else:
            status = ExecutionStatus.SUCCESS

        order_id = f"KT-AUTO-{uuid4().hex[:6].upper()}"

        # Realistic risk delta calculation (A6 fix)
        daily_demand = 5  # default; refine later
        coverage = qty / max(1, daily_demand)
        risk_delta = -min(60.0, coverage * 4.0)
        revenue_delta = -int(cost * 0.5) if cost else -500000
        if self._orders_executed > 0:
            risk_delta /= 2
            revenue_delta //= 2
        self._orders_executed += 1

        diff = {
            "inventory": {sku: qty},  # sandbox.apply_diff adds this delta
            "open_orders": [{
                "order_id": order_id,
                "supplier": supplier,
                "sku": sku,
                "qty": qty,
                "status": "placed",
                "value_pkr": cost,
            }],
            "supplier_status": {supplier: "active"},
            "risk_metrics": {
                "stockout_risk_pct": risk_delta,
                "revenue_at_risk_pkr": revenue_delta,
                "days_of_stock_remaining": max(1, int(coverage)),
            },
        }
        self.sandbox.apply_diff(diff)

        return ExecutionResult(
            action_id=action.id,
            status=status,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _exec_adjust_eta(self, action: Action, start: float) -> ExecutionResult:
        days_added = int(action.params.get("days_to_add", action.params.get("days", 5)))
        new_etas = {}

        for order_id, eta_str in self.sandbox.state.customer_etas.items():
            try:
                eta = datetime.fromisoformat(eta_str)
                new_etas[order_id] = (eta + timedelta(days=days_added)).date().isoformat()
            except (ValueError, TypeError):
                new_etas[order_id] = eta_str

        diff = {"customer_etas": new_etas}
        self.sandbox.apply_diff(diff)

        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.SUCCESS,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _exec_schedule_monitor(self, action: Action, start: float) -> ExecutionResult:
        diff = {"scheduled_checks": [{
            "scenario_id": self.scenario_id,
            "check_at": (datetime.utcnow() + timedelta(hours=24)).isoformat(),
            "reason": action.rationale,
        }]}
        self.sandbox.apply_diff(diff)
        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.SUCCESS,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _exec_investigate(self, action: Action, start: float) -> ExecutionResult:
        diff = {"investigations": [{
            "reason": action.rationale,
            "params": action.params,
            "triggered_at": datetime.utcnow().isoformat(),
        }]}
        self.sandbox.apply_diff(diff)
        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.SUCCESS,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _exec_rollback(self, action: Action, start: float) -> ExecutionResult:
        # Rollback to last snapshot
        if self.sandbox._snapshots:
            self.sandbox.rollback(len(self.sandbox._snapshots) - 1)
        diff = {"rolled_back": True}
        return ExecutionResult(
            action_id=action.id,
            status=ExecutionStatus.ROLLED_BACK,
            state_diff=diff,
            latency_ms=int((time.time() - start) * 1000),
            tokens_used=0,
        )

    def _topo_sort(self, actions: list[Action]) -> list[Action]:
        by_id = {a.id: a for a in actions}
        visited: set[str] = set()
        order: list[Action] = []

        def visit(aid: str):
            if aid in visited:
                return
            visited.add(aid)
            a = by_id.get(aid)
            if not a:
                return
            for d in a.depends_on:
                visit(d)
            order.append(a)

        for a in actions:
            visit(a.id)
        return order
