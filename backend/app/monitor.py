import asyncio
import logging
import time
from datetime import datetime, timezone, timedelta
import yaml
from pathlib import Path
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from app.config import settings
from app.scenario_loader import load_initial_state
from app import database as db

log = logging.getLogger(__name__)

scheduler = AsyncIOScheduler()

_last_trigger: dict[str, float] = {}
_interval_seconds: int = 60
_last_check_at: datetime | None = None

async def check_thresholds():
    global _last_check_at
    _last_check_at = datetime.now(timezone.utc)
    now = time.time()

    scenarios = ["S1", "S2", "S3"]
    best_scenario: str | None = None
    best_reason: str | None = None
    best_breach: float = 0.0

    for scenario_id in scenarios:
        try:
            # Fast in-memory check first
            if now - _last_trigger.get(scenario_id, 0) < 600:
                continue

            # DB-backed cooldown (survives reloads)
            conn = await db.get_conn()
            conn.row_factory = db.aiosqlite.Row
            cursor = await conn.execute(
                "SELECT last_triggered_at FROM monitor_cooldowns WHERE scenario_id = ?",
                (scenario_id,)
            )
            row = await cursor.fetchone()
            if row and (now - row["last_triggered_at"]) < 600:
                continue

            # Check for recent runs
            cursor = await conn.execute(
                "SELECT started_at FROM runs WHERE scenario_id = ? ORDER BY started_at DESC LIMIT 1",
                (scenario_id,)
            )
            row = await cursor.fetchone()
            if row:
                last_run_time = datetime.fromisoformat(row["started_at"])
                if last_run_time.tzinfo is None:
                    last_run_time = last_run_time.replace(tzinfo=timezone.utc)
                if datetime.now(timezone.utc) - last_run_time < timedelta(minutes=10):
                    continue

            # Load state and config — use to_thread so file I/O doesn't block the event loop
            config_path = Path(settings.SCENARIOS_DIR) / scenario_id / "config.yaml"
            if not config_path.exists():
                continue

            def _read_config(path=config_path):
                with open(path) as f:
                    return yaml.safe_load(f) or {}
            config = await asyncio.to_thread(_read_config)

            # Verify all source files exist
            sources = config.get("sources", [])
            scenario_dir = Path(settings.SCENARIOS_DIR) / scenario_id
            if not all((scenario_dir / src.get("file", "")).exists() for src in sources):
                continue

            if not (scenario_dir / "initial_state.json").exists():
                continue

            thresholds = config.get("thresholds", {})
            stockout_thresh = thresholds.get("stockout_risk_pct", 100)
            revenue_thresh = thresholds.get("revenue_at_risk_pkr", 9999999999)

            state = load_initial_state(scenario_id)
            reason: str | None = None
            breach: float = 0.0

            if state.risk_metrics.stockout_risk_pct > stockout_thresh:
                breach = state.risk_metrics.stockout_risk_pct - stockout_thresh
                reason = f"stockout_risk_pct = {state.risk_metrics.stockout_risk_pct}% > threshold {stockout_thresh}%"
            elif state.risk_metrics.revenue_at_risk_pkr > revenue_thresh:
                breach = float(state.risk_metrics.revenue_at_risk_pkr - revenue_thresh)
                reason = f"revenue_at_risk_pkr = Rs {state.risk_metrics.revenue_at_risk_pkr} > threshold Rs {revenue_thresh}"
            else:
                for supplier, status in state.supplier_status.items():
                    if status == "silent":
                        reason = f"supplier_status for {supplier} is silent"
                        breach = 1.0
                        break

            if reason and breach > best_breach:
                best_scenario = scenario_id
                best_reason = reason
                best_breach = breach

        except Exception as e:
            log.error("threshold check failed for %s: %s", scenario_id, e)

    if best_scenario and best_reason:
        ts = time.time()
        _last_trigger[best_scenario] = ts

        # Persist cooldown to DB so it survives reloads
        conn = await db.get_conn()
        await conn.execute(
            "INSERT OR REPLACE INTO monitor_cooldowns (scenario_id, last_triggered_at) VALUES (?, ?)",
            (best_scenario, ts)
        )
        await conn.commit()

        log.info("autonomous trigger: scenario=%s reason=%s", best_scenario, best_reason)

        # Call the run handler in-process to avoid an HTTP self-loop (which
        # breaks when API_KEY is set, and is brittle if the port changes).
        from app.routes.scenarios import _active_runs, _execute_run
        from app.schemas import RunSummary
        if best_scenario not in _active_runs:
            run = RunSummary(
                scenario_id=best_scenario,
                trigger_type="autonomous",
                trigger_reason=best_reason,
            )
            await db.create_run(run)
            asyncio.create_task(_execute_run(run.run_id, best_scenario, False))

def get_interval() -> int:
    return _interval_seconds

def set_interval(seconds: int) -> None:
    global _interval_seconds
    _interval_seconds = seconds
    if scheduler.get_job('threshold_check'):
        scheduler.reschedule_job('threshold_check', trigger='interval', seconds=seconds)

def start_monitor():
    scheduler.add_job(check_thresholds, 'interval', seconds=_interval_seconds, id='threshold_check')
    scheduler.start()

def stop_monitor():
    scheduler.shutdown()
