"""Scenario endpoints — list and trigger runs (SRS §7.3)."""
from __future__ import annotations
import asyncio
from fastapi import APIRouter, BackgroundTasks, HTTPException
from app.schemas import RunStartResponse, RunSummary, ScenarioInfo, RunStartRequest
from app.scenario_loader import (
    list_scenarios, load_initial_state, VALID_SCENARIO_IDS,
)
from app.sandbox import Sandbox
from app.agents.supervisor import SupervisorAgent
from app import database as db

router = APIRouter(prefix="/scenarios", tags=["scenarios"])

# Tracks scenario IDs that currently have a run in progress.
# Prevents spawning duplicate concurrent runs for the same scenario.
_active_runs: set[str] = set()


@router.get("/", response_model=list[ScenarioInfo])
async def get_scenarios():
    """List all available scenarios (FR-6.1)."""
    return list_scenarios()


@router.post("/{scenario_id}/run", response_model=RunStartResponse)
async def run_scenario(scenario_id: str, background_tasks: BackgroundTasks, offline: bool = False, req: RunStartRequest | None = None):
    """Start a scenario run (SRS §7.3: POST /scenarios/{id}/run)."""
    if scenario_id not in VALID_SCENARIO_IDS:
        raise HTTPException(status_code=400, detail=f"Unknown scenario_id: {scenario_id}")
    if scenario_id in _active_runs:
        raise HTTPException(status_code=409, detail=f"Scenario {scenario_id} already has a run in progress")
    trigger_type = req.trigger_type if req else "manual"
    trigger_reason = req.trigger_reason if req else None
    run = RunSummary(scenario_id=scenario_id, trigger_type=trigger_type, trigger_reason=trigger_reason)
    await db.create_run(run)

    background_tasks.add_task(_execute_run, run.run_id, scenario_id, offline)

    return RunStartResponse(run_id=run.run_id, scenario_id=scenario_id)


async def _execute_run(run_id: str, scenario_id: str, offline: bool = False) -> None:
    """Background task: load initial state, run supervisor pipeline."""
    from app.config import offline_mode_var
    from app.trace_logger import trace_logger
    from app.schemas import TraceEvent
    _active_runs.add(scenario_id)
    token = offline_mode_var.set(offline)
    try:
        initial_state = load_initial_state(scenario_id)
        sandbox = Sandbox(initial_state)
        await sandbox.persist_snapshot(run_id, "pre_run")

        supervisor = SupervisorAgent(run_id, sandbox, scenario_id=scenario_id)
        await supervisor.run(scenario_id)
    except Exception as e:
        import logging
        logging.getLogger(__name__).exception(
            "run failed [run_id=%s scenario=%s]", run_id, scenario_id
        )
        await db.update_run(run_id, phase="failed", error=str(e))
        # Emit a visible failure event so SSE clients see the error, not a silent done.
        await trace_logger.emit(TraceEvent(
            run_id=run_id, agent_name="supervisor", event_type="run_failed",
            output_summary=f"Run failed: {e}",
            detail={"error": str(e)},
        ))
        await trace_logger.emit_done(run_id)
    finally:
        _active_runs.discard(scenario_id)
        offline_mode_var.reset(token)

