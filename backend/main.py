"""StockSense Backend — FastAPI entry point."""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db
from app.routes import health, scenarios, runs, monitor_config
from app.monitor import start_monitor, stop_monitor

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    start_monitor()
    yield
    stop_monitor()

app = FastAPI(
    title="StockSense API",
    description="Autonomous Content-to-Action Agent backend",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])

app.include_router(health.router)
app.include_router(scenarios.router)
app.include_router(runs.router)
app.include_router(monitor_config.router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
