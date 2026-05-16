"""Scenario endpoints — list and trigger runs (SRS §7.3)."""
from __future__ import annotations
import asyncio
from fastapi import APIRouter, BackgroundTasks
from app.schemas import RunStartResponse, RunSummary, ScenarioInfo
from app.scenario_loader import list_scenarios, load_sources, load_initial_state
from app.sandbox import Sandbox
from app.agents.supervisor import SupervisorAgent
from app import database as db

router = APIRouter(prefix="/scenarios", tags=["scenarios"])


@router.get("/", response_model=list[ScenarioInfo])
async def get_scenarios():
    """List all available scenarios (FR-6.1)."""
    return list_scenarios()


@router.post("/{scenario_id}/run", response_model=RunStartResponse)
async def run_scenario(scenario_id: str, background_tasks: BackgroundTasks):
    """Start a scenario run (SRS §7.3: POST /scenarios/{id}/run)."""
    run = RunSummary(scenario_id=scenario_id)
    await db.create_run(run)

    background_tasks.add_task(_execute_run, run.run_id, scenario_id)

    return RunStartResponse(run_id=run.run_id, scenario_id=scenario_id)


async def _execute_run(run_id: str, scenario_id: str) -> None:
    """Background task: load sources, run supervisor pipeline."""
    try:
        sources = load_sources(scenario_id)
        initial_state = load_initial_state(scenario_id)
        sandbox = Sandbox(initial_state)
        await sandbox.persist_snapshot(run_id, "pre_run")

        supervisor = SupervisorAgent(run_id, sandbox)
        await supervisor.run(sources)
    except Exception as e:
        import traceback
        import sys
        tb = traceback.format_exc()
        print("Run Failed:", tb, file=sys.stderr, flush=True)
        await db.update_run(run_id, phase="failed", error=str(e))
        from app.trace_logger import trace_logger
        await trace_logger.emit_done(run_id)
