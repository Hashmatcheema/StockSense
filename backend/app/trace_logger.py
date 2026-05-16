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

    # ── SSE Generator ────────────────────────────────────────────────────────

    async def event_stream(self, run_id: str) -> AsyncGenerator[str, None]:
        """Yield SSE-formatted data strings for a run."""
        q = self.subscribe(run_id)
        try:
            while True:
                data = await q.get()
                if data is None:
                    # Run complete
                    yield f"event: done\ndata: {{}}\n\n"
                    break
                yield f"data: {data}\n\n"
        finally:
            self.unsubscribe(run_id, q)


# Module-level singleton
trace_logger = TraceLogger()
