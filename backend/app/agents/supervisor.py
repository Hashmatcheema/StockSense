"""Supervisor Agent — orchestrates the full agent crew (SRS §3.3)."""

from __future__ import annotations
import time
from app.agents.base import BaseAgent
from app.agents.ingestion import IngestionAgent
from app.agents.insight import InsightAgent
from app.agents.planner import PlannerAgent
from app.agents.executor import ExecutorAgent
from app.sandbox import Sandbox
from app.schemas import RunPhase, SourceDocument, ActionPlan, StateDiff
from app.trace_logger import trace_logger
from app import database as db


class SupervisorAgent(BaseAgent):
    name = "supervisor"

    def __init__(self, run_id: str, sandbox: Sandbox) -> None:
        super().__init__(run_id)
        self.sandbox = sandbox

    async def run(self, input_data: list[SourceDocument]) -> dict:
        run_start = time.time()
        await self.emit_event("agent_start", input_summary="Supervisor starting crew pipeline")
        await db.update_run(self.run_id, phase=RunPhase.INGESTION.value)

        # 1. Ingestion
        ingestion = IngestionAgent(self.run_id)
        accepted = await ingestion.run(input_data)

        # 2. Insight
        await db.update_run(self.run_id, phase=RunPhase.INSIGHT.value)
        insight = InsightAgent(self.run_id)
        insight_result = await insight.run(accepted)

        # 3. Planning
        await db.update_run(self.run_id, phase=RunPhase.PLANNING.value)
        planner = PlannerAgent(self.run_id)
        plan = await planner.run(insight_result)

        # 4. Execution
        await db.update_run(self.run_id, phase=RunPhase.EXECUTION.value)
        executor = ExecutorAgent(self.run_id, self.sandbox)
        results = await executor.run(plan)

        # Compute state diff
        state_diff = self.sandbox.compute_diff()

        # Aggregate stats
        total_ms = int((time.time() - run_start) * 1000)
        total_tokens = (ingestion._total_tokens + insight._total_tokens +
                       planner._total_tokens + executor._total_tokens)

        await db.update_run(self.run_id,
            phase=RunPhase.COMPLETED.value,
            total_latency_ms=total_ms, total_tokens_used=total_tokens,
            state_before=self.sandbox.initial_state.model_dump_json(),
            state_after=self.sandbox.state.model_dump_json(),
            action_plan=plan.model_dump_json())

        await self.emit_event("agent_end",
            output_summary=f"Pipeline complete in {total_ms}ms, {total_tokens} tokens",
            detail={"total_latency_ms": total_ms, "total_tokens": total_tokens})

        await trace_logger.emit_done(self.run_id)

        return {
            "plan": plan, "results": results, "state_diff": state_diff,
            "total_latency_ms": total_ms, "total_tokens": total_tokens,
        }
