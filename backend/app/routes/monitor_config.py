from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime, timezone
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
        "last_check_ago_seconds": last_check_ago
    }

@router.put("")
async def update_config(update: ConfigUpdate):
    if update.interval_seconds < 10 or update.interval_seconds > 86400:
        raise HTTPException(status_code=400, detail="Interval must be between 10 and 86400 seconds")
    set_interval(update.interval_seconds)
    return await get_config()
