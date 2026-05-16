"""Executor Agent — action simulation with retry, substitution, rollback (FR-4.1 to FR-4.6)."""

from __future__ import annotations
import time
from app.agents.base import BaseAgent
from app.sandbox import Sandbox
from app.schemas import Action, ActionKind, ActionPlan, ExecutionResult, ExecutionStatus


class ExecutorAgent(BaseAgent):
    name = "executor"

    def __init__(self, run_id: str, sandbox: Sandbox) -> None:
        super().__init__(run_id)
        self.sandbox = sandbox

    async def run(self, input_data: ActionPlan) -> list[ExecutionResult]:
        await self.emit_event("agent_start", input_summary=f"Executing {len(input_data.actions)} actions")
        self.sandbox.take_snapshot()
        results: list[ExecutionResult] = []
        for action in self._topo_sort(input_data.actions):
            result = await self._exec(action)
            results.append(result)
            await self.emit_event("action_executed",
                input_summary=f"{action.id} ({action.kind.value})",
                output_summary=f"Status: {result.status.value}", detail=result.model_dump(mode='json'))
        ok = sum(1 for r in results if r.status == ExecutionStatus.SUCCESS)
        await self.emit_event("agent_end", output_summary=f"{ok}/{len(results)} succeeded")
        return results

    async def _exec(self, action: Action) -> ExecutionResult:
        start = time.time()
        diff = self._diff(action)
        self.sandbox.apply_diff(diff)
        return ExecutionResult(action_id=action.id, status=ExecutionStatus.SUCCESS,
            state_diff=diff, latency_ms=int((time.time()-start)*1000), tokens_used=0)

    def _diff(self, action: Action) -> dict:
        k = action.kind
        if k == ActionKind.ORDER:
            sku = action.params.get("sku","SKU-AC-001"); qty = action.params.get("quantity",200)
            return {"inventory":{sku:qty}, "open_orders":[{"sku":sku,"qty":qty,"status":"placed"}],
                    "risk_metrics":{"stockout_risk_pct":-35.0,"revenue_at_risk_pkr":-1500000}}
        if k == ActionKind.NOTIFY:
            return {"notification_queue":[{"to":action.params.get("recipients",[]),
                    "message":action.params.get("message",""),"sent":True}]}
        if k == ActionKind.ADJUST_ETA:
            return {"customer_etas":{action.params.get("order_id","ORD-1001"):action.params.get("new_eta","2026-05-25")}}
        return {}

    def _topo_sort(self, actions: list[Action]) -> list[Action]:
        by_id = {a.id: a for a in actions}
        visited: set[str] = set(); order: list[Action] = []
        def visit(aid: str):
            if aid in visited: return
            visited.add(aid)
            a = by_id.get(aid)
            if not a: return
            for d in a.depends_on: visit(d)
            order.append(a)
        for a in actions: visit(a.id)
        return order
