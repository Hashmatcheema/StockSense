"""Application configuration — loads settings from .env."""

from __future__ import annotations

import os
from pathlib import Path
from dotenv import load_dotenv

# ── locate .env relative to this file ────────────────────────────────────────
_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(_ENV_PATH)


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

    # Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))

    # Scenarios base path
    SCENARIOS_DIR: str = str(Path(__file__).resolve().parent.parent.parent / "scenarios")

    # Offline / cache
    OFFLINE_MODE: bool = os.getenv("OFFLINE_MODE", "false").lower() == "true"
    CACHE_DIR: str = str(Path(__file__).resolve().parent.parent / "cache")


settings = Settings()
