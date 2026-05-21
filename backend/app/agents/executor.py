"""Executor Agent — action simulation with retry, substitution, rollback (FR-4.1 to FR-4.6)."""

from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone
from uuid import uuid4

log = logging.getLogger(__name__)

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
        
        # Load scenario_config.json if it exists
        import json
        import pathlib
        from app.config import settings
        self.scenario_config = {}
        if self.scenario_id:
            from app.scenario_loader import validate_scenario_id
            validate_scenario_id(self.scenario_id)
            config_file = pathlib.Path(settings.SCENARIOS_DIR) / self.scenario_id / "scenario_config.json"
            if config_file.exists():
                try:
                    with open(config_file, "r", encoding="utf-8") as f:
                        self.scenario_config = json.load(f)
                except Exception as exc:
                    log.warning("scenario_config load failed for %s: %s", self.scenario_id, exc)

    async def run(self, input_data: ActionPlan) -> list[ExecutionResult]:
        await self.emit_event("agent_start",
            input_summary=f"Executing {len(input_data.actions)} actions against sandbox")
        self.sandbox.take_snapshot()

        results: list[ExecutionResult] = []
        n_success = 0
        n_retried = 0
        n_rolled_back = 0
        
        retried_actions = set()

        for action in self._topo_sort(input_data.actions):
            # Check if any dependency of this action was retried or failed
            # If so, and we have rollback trigger, roll back this action!
            dep_retried = any(d in retried_actions for d in action.depends_on)
            rollback_trigger = self.scenario_config.get("dependent_action_rollback_trigger")
            
            is_rollback_target = False
            if dep_retried and rollback_trigger:
                # Find if the dependency was of kind rollback_trigger
                for d_id in action.depends_on:
                    dep_action = next((a for a in input_data.actions if a.id == d_id), None)
                    if dep_action and dep_action.kind.value == rollback_trigger:
                        is_rollback_target = True
                        break

            if is_rollback_target:
                # Dependency was retried/failed — skip this action without executing it.
                # We must NOT call sandbox.rollback() here because the action was never
                # applied; there is nothing to undo.
                await self.emit_event("action_failed",
                    input_summary=f"{action.id} ({action.kind.value})",
                    output_summary=f"Skipped: dependency {rollback_trigger} failed/retried.",
                    detail={"action_id": action.id, "error": "Dependency failed/retried"})
                result = ExecutionResult(
                    action_id=action.id,
                    status=ExecutionStatus.ROLLED_BACK,
                    state_diff={},
                    latency_ms=0,
                    tokens_used=0,
                    error="Skipped: dependency failed/retried",
                )
                results.append(result)
                n_rolled_back += 1
            else:
                result = await self._exec(action)
                results.append(result)
                if result.status == ExecutionStatus.SUCCESS:
                    n_success += 1
                elif result.status == ExecutionStatus.RETRIED:
                    n_retried += 1
                    retried_actions.add(action.id)
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
            "timestamp": datetime.now(timezone.utc).isoformat(),
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
        mock_fail = self.scenario_config.get("mock_supplier_fail_first_attempt", False)
        if (self.scenario_id == "S3" or mock_fail) and not self._s3_retry_done:
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
            "check_at": (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat(),
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
            "triggered_at": datetime.now(timezone.utc).isoformat(),
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
        in_stack: set[str] = set()
        order: list[Action] = []

        def visit(aid: str) -> None:
            if aid in visited:
                return
            if aid in in_stack:
                log.warning("dependency cycle detected at action %s — skipping edge", aid)
                return
            a = by_id.get(aid)
            if not a:
                return
            in_stack.add(aid)
            for d in a.depends_on:
                visit(d)
            in_stack.discard(aid)
            visited.add(aid)
            order.append(a)

        for a in actions:
            visit(a.id)
        return order
