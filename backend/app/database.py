"""SQLite database layer — async via aiosqlite (SRS §5.5, NFR-5.3)."""

from __future__ import annotations

import json
import aiosqlite
from pathlib import Path
from datetime import datetime

from app.config import settings
from app.schemas import TraceEvent, RunSummary, RunPhase


_DB_PATH = settings.DB_PATH

# ── Schema ───────────────────────────────────────────────────────────────────

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS runs (
    run_id          TEXT PRIMARY KEY,
    scenario_id     TEXT NOT NULL,
    phase           TEXT NOT NULL DEFAULT 'pending',
    started_at      TEXT NOT NULL,
    completed_at    TEXT,
    total_latency_ms INTEGER DEFAULT 0,
    total_tokens_used INTEGER DEFAULT 0,
    total_cost_usd  REAL DEFAULT 0.0,
    error           TEXT,
    state_before    TEXT,
    state_after     TEXT,
    action_plan     TEXT
);

CREATE TABLE IF NOT EXISTS trace_events (
    id              TEXT PRIMARY KEY,
    run_id          TEXT NOT NULL,
    agent_name      TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    input_summary   TEXT DEFAULT '',
    output_summary  TEXT DEFAULT '',
    detail          TEXT,
    latency_ms      INTEGER DEFAULT 0,
    tokens_used     INTEGER DEFAULT 0,
    timestamp       TEXT NOT NULL,
    FOREIGN KEY (run_id) REFERENCES runs(run_id)
);

CREATE TABLE IF NOT EXISTS sandbox_snapshots (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          TEXT NOT NULL,
    snapshot_label  TEXT NOT NULL,
    state_json      TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    FOREIGN KEY (run_id) REFERENCES runs(run_id)
);

CREATE INDEX IF NOT EXISTS idx_trace_run ON trace_events(run_id);
CREATE INDEX IF NOT EXISTS idx_snapshot_run ON sandbox_snapshots(run_id);
"""


async def init_db() -> None:
    """Create tables if they don't exist."""
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.executescript(_SCHEMA_SQL)
        await db.commit()


# ── Runs CRUD ────────────────────────────────────────────────────────────────

async def create_run(run: RunSummary) -> None:
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.execute(
            """INSERT INTO runs (run_id, scenario_id, phase, started_at)
               VALUES (?, ?, ?, ?)""",
            (run.run_id, run.scenario_id, run.phase.value, run.started_at.isoformat()),
        )
        await db.commit()


async def update_run(run_id: str, **kwargs) -> None:
    """Update run fields. Pass only the columns you want to change."""
    allowed = {
        "phase", "completed_at", "total_latency_ms", "total_tokens_used",
        "total_cost_usd", "error", "state_before", "state_after", "action_plan",
    }
    parts, vals = [], []
    for k, v in kwargs.items():
        if k not in allowed:
            continue
        parts.append(f"{k} = ?")
        vals.append(v)
    if not parts:
        return
    vals.append(run_id)
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.execute(f"UPDATE runs SET {', '.join(parts)} WHERE run_id = ?", vals)
        await db.commit()


async def get_run(run_id: str) -> dict | None:
    async with aiosqlite.connect(_DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM runs WHERE run_id = ?", (run_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None


# ── Trace Events CRUD ────────────────────────────────────────────────────────

async def insert_trace_event(event: TraceEvent) -> None:
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.execute(
            """INSERT INTO trace_events
               (id, run_id, agent_name, event_type, input_summary, output_summary,
                detail, latency_ms, tokens_used, timestamp)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                event.id, event.run_id, event.agent_name, event.event_type,
                event.input_summary, event.output_summary,
                json.dumps(event.detail, default=str) if event.detail else None,
                event.latency_ms, event.tokens_used,
                event.timestamp.isoformat(),
            ),
        )
        await db.commit()


async def get_trace_events(run_id: str) -> list[dict]:
    async with aiosqlite.connect(_DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM trace_events WHERE run_id = ? ORDER BY timestamp",
            (run_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]


# ── Sandbox Snapshots ────────────────────────────────────────────────────────

async def save_snapshot(run_id: str, label: str, state_json: str) -> None:
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.execute(
            """INSERT INTO sandbox_snapshots (run_id, snapshot_label, state_json, created_at)
               VALUES (?, ?, ?, ?)""",
            (run_id, label, state_json, datetime.utcnow().isoformat()),
        )
        await db.commit()


async def get_snapshot(run_id: str, label: str) -> str | None:
    async with aiosqlite.connect(_DB_PATH) as db:
        cursor = await db.execute(
            "SELECT state_json FROM sandbox_snapshots WHERE run_id = ? AND snapshot_label = ?",
            (run_id, label),
        )
        row = await cursor.fetchone()
        return row[0] if row else None
