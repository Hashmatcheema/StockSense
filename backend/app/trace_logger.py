"""Trace logger — persists and streams agent trace events (SRS §4.5)."""

from __future__ import annotations

import asyncio
import json
from datetime import datetime
from typing import AsyncGenerator

from app.schemas import TraceEvent
from app import database as db


class TraceLogger:
    """Manages trace event persistence and SSE broadcasting."""

    def __init__(self) -> None:
        # run_id → list of asyncio.Queue (one per SSE subscriber)
        self._subscribers: dict[str, list[asyncio.Queue]] = {}
        # Per-run lock to prevent race between replay and subscribe
        self._locks: dict[str, asyncio.Lock] = {}

    def _get_lock(self, run_id: str) -> asyncio.Lock:
        if run_id not in self._locks:
            self._locks[run_id] = asyncio.Lock()
        return self._locks[run_id]

    # ── Subscribe / Unsubscribe ──────────────────────────────────────────────

    def subscribe(self, run_id: str) -> asyncio.Queue:
        """Register a new SSE subscriber for a run."""
        q: asyncio.Queue = asyncio.Queue()
        self._subscribers.setdefault(run_id, []).append(q)
        return q

    def unsubscribe(self, run_id: str, q: asyncio.Queue) -> None:
        subs = self._subscribers.get(run_id, [])
        if q in subs:
            subs.remove(q)

    # ── Emit ─────────────────────────────────────────────────────────────────

    async def emit(self, event: TraceEvent) -> None:
        """Persist event to SQLite and broadcast to SSE subscribers."""
        # Persist
        await db.insert_trace_event(event)

        # Broadcast to all subscribers of this run
        data = json.dumps(event.model_dump(), default=str)
        for q in self._subscribers.get(event.run_id, []):
            await q.put(data)

    async def emit_done(self, run_id: str) -> None:
        """Signal that the run is complete — send a sentinel and clean up."""
        for q in self._subscribers.get(run_id, []):
            await q.put(None)  # sentinel
        self._subscribers.pop(run_id, None)
        self._locks.pop(run_id, None)

    # ── SSE Generator ────────────────────────────────────────────────────────

    async def event_stream(self, run_id: str) -> AsyncGenerator[str, None]:
        """Yield SSE-formatted data strings for a run.

        Fix for A1 race condition: replay all persisted events first,
        then subscribe for live events. A per-run lock ensures no event
        is missed or duplicated during the transition.
        """
        lock = self._get_lock(run_id)
        async with lock:
            # Step 1: Replay all persisted events
            persisted = await db.get_trace_events(run_id)
            replayed_ids = set()
            for row in persisted:
                event_id = row.get("id", "")
                replayed_ids.add(event_id)
                # Re-parse detail if it's a JSON string
                detail = row.get("detail")
                if isinstance(detail, str):
                    try:
                        detail = json.loads(detail)
                    except (json.JSONDecodeError, TypeError):
                        pass
                event_data = {
                    "id": event_id,
                    "run_id": row.get("run_id", run_id),
                    "agent_name": row.get("agent_name", ""),
                    "event_type": row.get("event_type", ""),
                    "input_summary": row.get("input_summary", ""),
                    "output_summary": row.get("output_summary", ""),
                    "detail": detail,
                    "latency_ms": row.get("latency_ms", 0),
                    "tokens_used": row.get("tokens_used", 0),
                    "timestamp": row.get("timestamp", ""),
                }
                yield f"data: {json.dumps(event_data, default=str)}\n\n"

            # Step 2: Subscribe for live events (while still holding lock)
            q = self.subscribe(run_id)

        # Step 3: Stream live events (lock released)
        try:
            while True:
                data = await q.get()
                if data is None:
                    # Run complete
                    yield f"event: done\ndata: {{}}\n\n"
                    break
                # Deduplicate: skip events already replayed
                try:
                    parsed = json.loads(data)
                    eid = parsed.get("id", "")
                    if eid in replayed_ids:
                        continue
                except (json.JSONDecodeError, TypeError):
                    pass
                yield f"data: {data}\n\n"
        finally:
            self.unsubscribe(run_id, q)


# Module-level singleton
trace_logger = TraceLogger()
