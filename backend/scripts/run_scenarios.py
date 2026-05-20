import asyncio
import sys
import os
from pathlib import Path

# Add backend to python path
sys.path.append(str(Path(__file__).resolve().parent.parent))

from app.sandbox import Sandbox
from app.scenario_loader import load_initial_state
from app.agents.supervisor import SupervisorAgent
from app import database as db
from app.config import settings

async def run_scenario(scenario_id: str):
    print(f"\n================ RUNNING {scenario_id} ================")
    initial_state = load_initial_state(scenario_id)
    sandbox = Sandbox(initial_state)
    run_id = f"test-run-{scenario_id}"
    
    # Clean previous DB runs for this ID if they clash
    await db.clear_run_if_exists(run_id)
    
    await sandbox.persist_snapshot(run_id, "pre_run")
    supervisor = SupervisorAgent(run_id, sandbox, scenario_id=scenario_id)
    result = await supervisor.run(scenario_id)
    print(f"Result of {scenario_id}:")
    print(f"Total Latency: {result.get('total_latency_ms')} ms")
    print(f"Total Tokens: {result.get('total_tokens')}")
    print(f"Plan Executable: {result.get('plan').is_executable}")
    print(f"State Diff: {result.get('state_diff')}")

async def main():
    settings.OFFLINE_MODE = True
    await db.init_db()
    # Run S1, S2, S3 in offline mode
    for sid in ["S1", "S2", "S3"]:
        try:
            await run_scenario(sid)
        except Exception as e:
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())
