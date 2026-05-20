from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime, timezone
from app.config import settings
from app.monitor import get_interval, set_interval, scheduler, _last_check_at

router = APIRouter(prefix="/monitor/config", tags=["monitor"])

class ConfigUpdate(BaseModel):
    interval_seconds: int

@router.get("")
async def get_config():
    interval = get_interval()
    job = scheduler.get_job('threshold_check')
    
    next_run_in = 0
    if job and job.next_run_time:
        diff = (job.next_run_time - datetime.now(timezone.utc)).total_seconds()
        next_run_in = max(0, int(diff))
        
    last_check_ago = 0
    if _last_check_at:
        diff = (datetime.now(timezone.utc) - _last_check_at).total_seconds()
        last_check_ago = max(0, int(diff))
        
    return {
        "interval_seconds": interval,
        "next_run_in_seconds": next_run_in,
        "last_check_ago_seconds": last_check_ago,
        # App-wide settings the client wants to keep in sync with the
        # backend (cost rate used for the live-run stats bar, model name
        # shown in Settings → About, server version).
        "gemini_cost_per_mtok": settings.GEMINI_COST_PER_MTOK,
        "gemini_model": settings.GEMINI_MODEL_FLASH,
        "app_version": settings.APP_VERSION,
        "company_name": settings.COMPANY_NAME,
    }

@router.put("")
async def update_config(update: ConfigUpdate):
    if update.interval_seconds < 10 or update.interval_seconds > 86400:
        raise HTTPException(status_code=400, detail="Interval must be between 10 and 86400 seconds")
    set_interval(update.interval_seconds)
    return await get_config()
