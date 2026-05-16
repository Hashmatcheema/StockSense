"""Run endpoints — trace streaming, state diffs, export (SRS §7.3)."""
from __future__ import annotations
import json
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from app import database as db
from app.trace_logger import trace_logger
from app.schemas import BusinessState, StateDiff, ActionPlan

router = APIRouter(prefix="/runs", tags=["runs"])


@router.get("/{run_id}")
async def get_run(run_id: str):
    """GET /runs/{run_id} — final state + trace summary."""
    run = await db.get_run(run_id)
    if not run:
        raise HTTPException(404, "Run not found")
    events = await db.get_trace_events(run_id)
    return {"run": run, "trace_events": events}


@router.get("/{run_id}/events")
async def stream_events(run_id: str):
    """GET /runs/{run_id}/events — SSE stream of agent events (FR-5.2)."""
    run = await db.get_run(run_id)
    if not run:
        raise HTTPException(404, "Run not found")

    async def gen():
        async for chunk in trace_logger.event_stream(run_id):
            yield chunk

    return StreamingResponse(gen(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive",
                 "X-Accel-Buffering": "no"})


@router.get("/{run_id}/state-diff")
async def get_state_diff(run_id: str):
    """GET /runs/{run_id}/state-diff — before vs after (FR-6.3)."""
    run = await db.get_run(run_id)
    if not run:
        raise HTTPException(404, "Run not found")
    before_json = run.get("state_before")
    after_json = run.get("state_after")
    if not before_json or not after_json:
        raise HTTPException(400, "Run not yet completed")
    before = BusinessState(**json.loads(before_json))
    after = BusinessState(**json.loads(after_json))
    from app.sandbox import Sandbox
    sb = Sandbox(before)
    sb._current = after
    diff = sb.compute_diff()
    return diff.model_dump()


@router.get("/{run_id}/export")
async def export_trace(run_id: str):
    """GET /runs/{run_id}/export — full trace as JSON file (FR-6.6)."""
    run = await db.get_run(run_id)
    if not run:
        raise HTTPException(404, "Run not found")
    events = await db.get_trace_events(run_id)
    export = {"run": run, "trace_events": events}
    return JSONResponse(content=export,
        headers={"Content-Disposition": f'attachment; filename="trace_{run_id}.json"'})
