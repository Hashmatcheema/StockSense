"""StockSense Backend — FastAPI entry point."""
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.config import settings
from app.database import init_db, close_conn
from app.routes import health, scenarios, runs, monitor_config
from app.monitor import start_monitor, stop_monitor

# Replace ad-hoc `print()` calls across agents/monitor with a structured
# logger. Per-module loggers (logging.getLogger(__name__)) inherit this
# config, so child modules just call `log.info(...)` / `log.error(...)`.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    if not settings.GEMINI_API_KEY:
        logging.getLogger(__name__).warning(
            "GEMINI_API_KEY is not set — live Gemini calls will fail at runtime"
        )
    await init_db()
    start_monitor()
    yield
    stop_monitor()
    await close_conn()

app = FastAPI(
    title="StockSense API",
    description="Autonomous Content-to-Action Agent backend",
    version="1.0.0",
    lifespan=lifespan,
)

_cors_origins = settings.CORS_ORIGINS
# allow_credentials=True is incompatible with allow_origins=['*'] — browsers
# reject credentialed requests to a wildcard origin. Disable credentials when
# the wildcard is in the list so the server doesn't crash on startup.
_allow_credentials = "*" not in _cors_origins
app.add_middleware(CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"])


@app.middleware("http")
async def api_key_guard(request: Request, call_next):
    """Reject requests missing a valid API key — only active when API_KEY is set in .env."""
    key = settings.API_KEY
    if key:
        # Allow health-check through without auth so load-balancers can probe
        if request.url.path != "/health":
            provided = request.headers.get("X-API-Key", "")
            if provided != key:
                return JSONResponse(status_code=401, content={"detail": "Invalid or missing API key"})
    return await call_next(request)


app.include_router(health.router)
app.include_router(scenarios.router)
app.include_router(runs.router)
app.include_router(monitor_config.router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=settings.HOST, port=settings.PORT, reload=True)
