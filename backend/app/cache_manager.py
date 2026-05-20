import asyncio
import hashlib
import json
import os
import time
from pathlib import Path
from app.config import settings

def _load_cache_file(f_path: Path):
    """Load cache file, validating that the response field is valid JSON. Returns (data, ok)."""
    try:
        with open(f_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        # Validate the response field is parseable JSON
        response_text = data.get("response", "")
        json.loads(response_text)  # Will raise if truncated/corrupt
        return data, True
    except Exception:
        return None, False


async def get_cached_or_generate(scenario_id: str, agent_name: str, call_type: str, prompt: str, generate_fn) -> tuple[str, int, int]:
    """
    Returns (response_text, latency_ms, tokens_used)
    In offline mode: loads from cache, preferring dummy files over hash-named files.
    In live mode: calls generate_fn and caches the result.
    """
    sid = scenario_id or "S1"

    prompt_hash = hashlib.sha256(prompt.encode("utf-8")).hexdigest()
    cache_dir = Path(settings.CACHE_DIR) / sid
    cache_file = cache_dir / f"{agent_name}_{call_type}_{prompt_hash}.json"

    if settings.is_offline:
        # First: try dummy files (more reliable than partial hash-named files)
        if cache_dir.exists():
            # Prefer _dummy.json files for the matching call type
            for f_path in sorted(cache_dir.iterdir()):
                if f_path.name.startswith(f"{agent_name}_{call_type}_") and "_dummy" in f_path.name:
                    data, ok = _load_cache_file(f_path)
                    if ok:
                        return data["response"], data.get("latency_ms", 100), data.get("tokens_used", 150)

            # Second: try exact hash match (from prior live run), validate it's not corrupt
            if cache_file.exists():
                data, ok = _load_cache_file(cache_file)
                if ok:
                    return data["response"], data.get("latency_ms", 100), data.get("tokens_used", 150)

            # Third: any matching call_type file
            for f_path in sorted(cache_dir.iterdir()):
                if f_path.name.startswith(f"{agent_name}_{call_type}_"):
                    data, ok = _load_cache_file(f_path)
                    if ok:
                        return data["response"], data.get("latency_ms", 100), data.get("tokens_used", 150)

        # Fallback defaults by call_type prefix
        if call_type.startswith("extract"):
            return '{"signals": []}', 100, 0
        elif call_type == "conflict":
            return '{"winning_signal_index": 0, "confidence": 0.5, "reason": "offline fallback"}', 100, 0
        elif call_type == "impact":
            return ('{"stockout_risk_pct": 50, "revenue_at_risk_pkr": 100000, '
                    '"days_of_stock_remaining": 5, "customers_affected": 5, '
                    '"primary_threat": "offline warning", "urgency": "medium"}'), 100, 0
        elif call_type == "plan":
            return ('{"actions": [], "total_estimated_impact_pkr": 0, '
                    '"is_executable": true, "plan_summary": "offline plan fallback"}'), 100, 0
        return '{}', 100, 0

    # Live mode: reuse a cached response on a prompt-hash hit if LIVE_CACHE
    # is enabled. Avoids re-charging for identical prompts during demo
    # replays. The cached file already contains the original latency/tokens.
    if settings.LIVE_CACHE and cache_file.exists():
        data, ok = _load_cache_file(cache_file)
        if ok:
            return data["response"], data.get("latency_ms", 100), data.get("tokens_used", 150)

    # Live mode: call generate_fn in a worker thread so we don't block the event loop
    t0 = time.time()
    resp = await asyncio.to_thread(generate_fn)
    latency = int((time.time() - t0) * 1000)

    tokens = 0
    if hasattr(resp, 'usage_metadata') and resp.usage_metadata:
        tokens = resp.usage_metadata.total_token_count

    response_text = resp.text

    # Save to cache (only if the response is valid JSON)
    try:
        json.loads(response_text)  # validate before saving
        cache_dir.mkdir(parents=True, exist_ok=True)
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump({
                "prompt": prompt,
                "response": response_text,
                "latency_ms": latency,
                "tokens_used": tokens
            }, f, indent=2)
    except Exception:
        pass  # Don't cache truncated responses

    return response_text, latency, tokens
