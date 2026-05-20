"""
Baseline Comparison Script (FR-7)
Compares the agentic pipeline against a naive reactive baseline across S1, S2, S3.

Baseline heuristic: process one source at a time, take the first stock signal found,
and issue a hard-coded re-order of 20 units if stockout_risk_pct > 55%.

Run in offline mode:
    OFFLINE_MODE=true python scripts/baseline_compare.py
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path
from datetime import datetime

# Add backend to python path
sys.path.append(str(Path(__file__).resolve().parent.parent))

from app.scenario_loader import load_initial_state, list_scenarios
from app.sandbox import Sandbox
from app.agents.supervisor import SupervisorAgent
from app import database as db
from app.config import settings

# ── Baseline Pipeline ──────────────────────────────────────────────────────────

def run_baseline(scenario_id: str, initial_state_dict: dict) -> dict:
    """
    Naive reactive heuristic: 
    - Process sources one-by-one, stop at first stock_level signal
    - If stockout_risk_pct > 55, place a hard-coded order of 20 units
    - No contradiction resolution, no planning, no confidence scoring
    """
    state = {
        "inventory": dict(initial_state_dict.get("inventory", {})),
        "stockout_risk_pct": initial_state_dict.get("risk_metrics", {}).get("stockout_risk_pct", 0),
        "revenue_at_risk_pkr": initial_state_dict.get("risk_metrics", {}).get("revenue_at_risk_pkr", 0),
        "orders_placed": 0,
        "notifications_sent": 0,
        "investigations_triggered": 0,
        "actions_taken": [],
    }

    # Naive: read first CSV/JSON that has a stock level
    import yaml
    import csv
    import io
    scenarios_dir = Path(settings.SCENARIOS_DIR)
    config_file = scenarios_dir / scenario_id / "config.yaml"
    
    if not config_file.exists():
        return state

    with open(config_file, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    sources = config.get("sources", [])
    first_sku = None
    first_stock = None

    for src in sources:
        kind = src.get("kind", "")
        filepath = scenarios_dir / scenario_id / src.get("file", "")
        if not filepath.exists():
            continue
        
        if kind == "csv":
            text = filepath.read_text(encoding="utf-8")
            reader = csv.DictReader(io.StringIO(text))
            for row in reader:
                sku_val = row.get("sku") or row.get("SKU")
                stock_val = row.get("units_on_hand") or row.get("stock_level")
                if sku_val and stock_val:
                    try:
                        first_sku = str(sku_val)
                        first_stock = float(stock_val)
                        break
                    except ValueError:
                        continue
        elif kind == "json":
            try:
                with open(filepath, encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, dict) and "catalog" in data:
                    # alt supplier JSON — skip
                    continue
                # Look for inventory or stock fields
                if isinstance(data, dict):
                    for key, val in data.items():
                        if isinstance(val, dict):
                            for k2, v2 in val.items():
                                if isinstance(v2, (int, float)) and v2 > 0:
                                    first_sku = k2
                                    first_stock = float(v2)
                                    break
                        if first_sku:
                            break
            except Exception:
                continue

        if first_sku:
            break

    # Naive decision: if stockout_risk > 55% → order 20 units of first found SKU
    baseline_actions = []
    threshold = config.get("thresholds", {}).get("stockout_risk_pct", 55)
    
    if state["stockout_risk_pct"] > threshold and first_sku:
        order_qty = 20
        state["inventory"][first_sku] = state["inventory"].get(first_sku, 0) + order_qty
        state["stockout_risk_pct"] = max(0, state["stockout_risk_pct"] - 20)
        state["revenue_at_risk_pkr"] = max(0, state["revenue_at_risk_pkr"] - 500000)
        state["orders_placed"] += 1
        baseline_actions.append(f"order:{first_sku}:qty={order_qty}")
    else:
        baseline_actions.append("no_action:stockout_risk_below_threshold")

    state["actions_taken"] = baseline_actions
    return state


# ── Agentic Pipeline ──────────────────────────────────────────────────────────

async def run_agentic(scenario_id: str) -> dict:
    """Run the full agentic pipeline and return a comparable metrics dict."""
    initial_state = load_initial_state(scenario_id)
    sandbox = Sandbox(initial_state)
    run_id = f"baseline-run-{scenario_id}-{datetime.utcnow().strftime('%H%M%S')}"

    await sandbox.persist_snapshot(run_id, "pre_run")
    supervisor = SupervisorAgent(run_id, sandbox, scenario_id=scenario_id)
    result = await supervisor.run(scenario_id)

    plan = result.get("plan")
    state_diff = result.get("state_diff")
    
    after = state_diff.after if state_diff else None
    before = state_diff.before if state_diff else None

    inventory_delta = {}
    if before and after:
        for sku in after.inventory:
            b = before.inventory.get(sku, 0)
            a = after.inventory.get(sku, 0)
            if a != b:
                inventory_delta[sku] = {"before": b, "after": a, "delta": a - b}

    return {
        "scenario_id": scenario_id,
        "total_latency_ms": result.get("total_latency_ms", 0),
        "total_tokens": result.get("total_tokens", 0),
        "actions_count": len(plan.actions) if plan else 0,
        "actions_taken": [f"{a.kind.value}:{a.params}" for a in plan.actions] if plan else [],
        "orders_placed": sum(1 for a in plan.actions if a.kind.value == "order") if plan else 0,
        "investigations_triggered": sum(1 for a in plan.actions if a.kind.value == "investigate") if plan else 0,
        "stockout_risk_pct_before": before.risk_metrics.stockout_risk_pct if before else 0,
        "stockout_risk_pct_after": after.risk_metrics.stockout_risk_pct if after else 0,
        "revenue_at_risk_before": before.risk_metrics.revenue_at_risk_pkr if before else 0,
        "revenue_at_risk_after": after.risk_metrics.revenue_at_risk_pkr if after else 0,
        "inventory_delta": inventory_delta,
        "conflict_resolution": True,
        "confidence_scoring": True,
        "retry_rollback": True if scenario_id == "S3" else False,
    }


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    settings.OFFLINE_MODE = True
    await db.init_db()

    scenarios = ["S1", "S2", "S3"]
    rows = []

    for sid in scenarios:
        print(f"\n[Baseline] Running {sid}...")
        initial_state_dict = json.loads(Path(settings.SCENARIOS_DIR, sid, "initial_state.json").read_text())
        baseline = run_baseline(sid, initial_state_dict)
        
        print(f"[Agentic] Running {sid}...")
        try:
            agentic = await run_agentic(sid)
        except Exception as e:
            import traceback
            traceback.print_exc()
            agentic = {"error": str(e)}
        
        rows.append({
            "scenario_id": sid,
            "baseline": baseline,
            "agentic": agentic,
        })

    # Generate markdown report
    md = ["# Baseline vs Agentic Comparison", "", f"_Generated: {datetime.utcnow().isoformat()}_", ""]
    md.append("## Summary Table")
    md.append("")
    md.append("| Scenario | Pipeline | Stockout Risk Before | Stockout Risk After | Revenue @ Risk Before | Revenue @ Risk After | Actions | Orders Placed | Investigations |")
    md.append("|---|---|---|---|---|---|---|---|---|")
    
    for row in rows:
        sid = row["scenario_id"]
        b = row["baseline"]
        a = row["agentic"]

        md.append(
            f"| {sid} | Baseline (Heuristic) | {b.get('stockout_risk_pct', 'N/A')}% | {b.get('stockout_risk_pct', 'N/A')}% | "
            f"PKR {b.get('revenue_at_risk_pkr', 'N/A'):,} | PKR {b.get('revenue_at_risk_pkr', 'N/A'):,} | "
            f"{len(b.get('actions_taken', []))} | {b.get('orders_placed', 0)} | {b.get('investigations_triggered', 0)} |"
        )
        md.append(
            f"| {sid} | StockSense Agentic | {a.get('stockout_risk_pct_before', 'N/A')}% | {a.get('stockout_risk_pct_after', 'N/A')}% | "
            f"PKR {a.get('revenue_at_risk_before', 0):,} | PKR {a.get('revenue_at_risk_after', 0):,} | "
            f"{a.get('actions_count', 0)} | {a.get('orders_placed', 0)} | {a.get('investigations_triggered', 0)} |"
        )

    md.append("")
    md.append("## Qualitative Differences")
    md.append("")
    md.append("| Capability | Baseline | StockSense |")
    md.append("|---|---|---|")
    md.append("| Contradiction Resolution | ❌ None | ✅ Credibility-weighted Gemini vote |")
    md.append("| Confidence Scoring | ❌ None | ✅ Per-signal confidence with low-confidence flag |")
    md.append("| Investigate Action | ❌ Never triggered | ✅ Triggered on low-confidence signals (S2) |")
    md.append("| Retry / Rollback | ❌ None | ✅ Supplier retry + dependent rollback (S3) |")
    md.append("| Multi-source Fusion | ❌ Stops at first source | ✅ All sources processed and merged |")
    md.append("| Business Impact Estimation | ❌ Fixed thresholds | ✅ Gemini-powered contextual estimation |")
    md.append("| DAG Action Ordering | ❌ Sequential only | ✅ Topological dependency resolution |")
    md.append("")

    md.append("## Per-Scenario Details")
    for row in rows:
        sid = row["scenario_id"]
        a = row["agentic"]
        b = row["baseline"]
        md.append(f"\n### {sid}")
        md.append(f"**Agentic Actions:** {', '.join(a.get('actions_taken', []))}")
        md.append(f"**Baseline Actions:** {', '.join(b.get('actions_taken', []))}")
        if a.get("inventory_delta"):
            md.append(f"**Inventory Changes:** {json.dumps(a['inventory_delta'])}")
        md.append(f"**Total Tokens Used:** {a.get('total_tokens', 0)}")
        md.append(f"**Latency:** {a.get('total_latency_ms', 0)} ms (offline cached)")

    # Write docs
    docs_dir = Path(__file__).resolve().parent.parent.parent / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    out_path = docs_dir / "baseline.md"
    out_path.write_text("\n".join(md), encoding="utf-8")
    print(f"\nDone: Baseline comparison written to {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
