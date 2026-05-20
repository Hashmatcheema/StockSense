"""Application configuration — loads settings from .env."""

from __future__ import annotations

import os
from pathlib import Path
from dotenv import load_dotenv

# ── locate .env relative to this file ────────────────────────────────────────
_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(_ENV_PATH)


from contextvars import ContextVar

offline_mode_var: ContextVar[bool] = ContextVar("offline_mode", default=False)


class Settings:
    """Centralised settings read from environment variables."""

    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODEL_PRO: str = os.getenv("GEMINI_MODEL_PRO", "gemini-2.5-flash")
    GEMINI_MODEL_FLASH: str = os.getenv("GEMINI_MODEL_FLASH", "gemini-2.5-flash")

    # Database
    DB_PATH: str = os.getenv("DB_PATH", str(Path(__file__).resolve().parent.parent / "stocksense.db"))

    # Agent tuning
    STALENESS_THRESHOLD_DAYS: int = int(os.getenv("STALENESS_THRESHOLD_DAYS", "14"))
    MAX_ACTIONS_PER_PLAN: int = 5
    MIN_ACTIONS_PER_PLAN: int = 3
    LOW_CONFIDENCE_THRESHOLD: float = 0.6
    MAX_RETRY_ATTEMPTS: int = 1
    MAX_SUBSTITUTION_ATTEMPTS: int = 1

    # Security
    API_KEY: str = os.getenv("API_KEY", "")
    # Default to localhost-only origins; set CORS_ORIGINS=* in .env for dev convenience.
    CORS_ORIGINS: list[str] = [
        o.strip() for o in os.getenv(
            "CORS_ORIGINS",
            "http://localhost:8000,http://localhost:3000,http://127.0.0.1:8000"
        ).split(",") if o.strip()
    ]

    # Branding — surfaced to the Flutter AppBar via /monitor/config
    COMPANY_NAME: str = os.getenv("COMPANY_NAME", "Khan Traders · Lahore")

    # Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))

    # Scenarios base path
    SCENARIOS_DIR: str = str(Path(__file__).resolve().parent.parent.parent / "scenarios")

    # Offline / cache
    OFFLINE_MODE: bool = os.getenv("OFFLINE_MODE", "false").lower() == "true"
    CACHE_DIR: str = str(Path(__file__).resolve().parent.parent / "cache")
    # When true, the cache_manager will reuse a cached Gemini response on
    # repeated prompts even in live mode — saves spend on demo replays. Set
    # to "false" if you want to force every call to hit Gemini.
    LIVE_CACHE: bool = os.getenv("LIVE_CACHE", "true").lower() == "true"

    # Pricing — surfaced to the Flutter app via /monitor/config so the
    # cost-per-million-tokens used in the live-run stats bar matches the
    # actual model billing rate without a client rebuild.
    GEMINI_COST_PER_MTOK: float = float(os.getenv("GEMINI_COST_PER_MTOK", "0.15"))

    # App version (surfaced to Settings → About)
    APP_VERSION: str = os.getenv("APP_VERSION", "1.0.0")

    @property
    def is_offline(self) -> bool:
        return offline_mode_var.get() or self.OFFLINE_MODE


settings = Settings()

