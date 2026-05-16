import asyncio
from app.schemas import RunSummary
from app.database import create_run, init_db
from app.routes.scenarios import _execute_run

async def main():
    await init_db()
    run = RunSummary(scenario_id='S1')
    await create_run(run)
    try:
        await _execute_run(run.run_id, 'S1')
    except Exception as e:
        import traceback
        traceback.print_exc()

asyncio.run(main())
