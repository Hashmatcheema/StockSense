import os
import json
from pathlib import Path

CACHE_DIR = Path(__file__).resolve().parent.parent / "cache"

def write_cache_file(scenario_id, agent_name, call_type, response_data):
    scen_dir = CACHE_DIR / scenario_id
    scen_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{agent_name}_{call_type}_dummy.json"
    filepath = scen_dir / filename
    
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump({
            "prompt": "dummy",
            "response": json.dumps(response_data),
            "latency_ms": 150,
            "tokens_used": 200
        }, f, indent=2)
    print(f"Wrote cache file: {filepath}")

def main():
    # ── S1 MOCK RESPONSES ────────────────────────────────────────────────────
    
    # 1. Ingest/Extract signals
    write_cache_file("S1", "insight", "extract_khan_warehouse_oct", {
        "signals": [
            {"kind": "stock_level", "sku": "AC-INV-12K-HAI", "metric": "units_on_hand", "value": 18, "delta_vs_baseline_pct": -40.0, "rationale": "Low warehouse stock of Haier ACs."},
            {"kind": "stock_level", "sku": "AC-INV-15K-ORL", "metric": "units_on_hand", "value": 7, "delta_vs_baseline_pct": -53.0, "rationale": "Depleted Orient AC units."}
        ]
    })
    
    write_cache_file("S1", "insight", "extract_sales_dashboard_lahore", {
        "signals": [
            {"kind": "sales_change", "sku": "AC-INV-12K-HAI", "metric": "pending_orders_unshipped", "value": 31, "delta_vs_baseline_pct": 25.0, "rationale": "Pending orders accumulated."}
        ]
    })
    
    write_cache_file("S1", "insight", "extract_supplier_email_karachi_cool", {
        "signals": [
            {"kind": "supplier_status", "sku": None, "metric": "delay_days", "value": 5, "delta_vs_baseline_pct": None, "rationale": "Karachi Cool supplier silent for 5 days."}
        ]
    })
    
    write_cache_file("S1", "insight", "extract_complaints_log_oct", {
        "signals": [
            {"kind": "complaint_cluster", "sku": None, "metric": "complaint_count", "value": 47, "delta_vs_baseline_pct": 15.0, "rationale": "Delayed delivery complaints are escalating."}
        ]
    })
    
    write_cache_file("S1", "insight", "extract_news_fuel_prices", {
        "signals": [
            {"kind": "external_shock", "sku": None, "metric": "fuel_price_pkr", "value": 266, "delta_vs_baseline_pct": 3.0, "rationale": "Fuel price hike of Rs 8 increases logistics costs."}
        ]
    })
    
    write_cache_file("S1", "insight", "extract_news_transport_strike", {
        "signals": [
            {"kind": "external_shock", "sku": None, "metric": "logistics_disruption_days", "value": 3, "delta_vs_baseline_pct": None, "rationale": "Transport strike blocking highways."}
        ]
    })
    
    # 2. Planner Impact Assesment S1
    write_cache_file("S1", "planner", "impact", {
        "stockout_risk_pct": 72,
        "revenue_at_risk_pkr": 3800000,
        "days_of_stock_remaining": 3,
        "customers_affected": 31,
        "primary_threat": "Supplier silence combined with transport strike blocks logistics.",
        "urgency": "critical"
    })
    
    # 3. Planner Action Plan S1
    write_cache_file("S1", "planner", "plan", {
        "actions": [
            {
                "id": "act-1",
                "kind": "validate",
                "params": {"sku": "AC-INV-12K-HAI"},
                "depends_on": [],
                "constraints_required": [],
                "rationale": "Verify actual AC stock at the warehouse before placing emergency order.",
                "feasible": True,
                "estimated_cost_pkr": 0
            },
            {
                "id": "act-2",
                "kind": "order",
                "params": {"sku": "AC-INV-12K-HAI", "quantity": 25, "supplier": "Lahore Electronics Hub"},
                "depends_on": ["act-1"],
                "constraints_required": ["budget_pkr"],
                "rationale": "Order 25 Haier AC units from local hub to bypass transport block.",
                "feasible": True,
                "estimated_cost_pkr": 3200000
            },
            {
                "id": "act-3",
                "kind": "notify",
                "params": {"recipients": ["procurement-team"], "message": "Emergency AC order placed."},
                "depends_on": ["act-2"],
                "constraints_required": [],
                "rationale": "Notify team of local order placement.",
                "feasible": True,
                "estimated_cost_pkr": 0
            }
        ],
        "total_estimated_impact_pkr": 3200000,
        "executable": True,
        "plan_summary": "Validate stock levels, order 25 units from local hub to prevent stockout, and notify the procurement team."
    })
    
    # ── S2 MOCK RESPONSES ────────────────────────────────────────────────────
    
    write_cache_file("S2", "insight", "extract_khan_warehouse_s2", {
        "signals": [
            {"kind": "stock_level", "sku": "SKU-117", "metric": "units_on_hand", "value": 240, "delta_vs_baseline_pct": 33.3, "rationale": "Warehouse report claims 240 units available."}
        ]
    })
    
    write_cache_file("S2", "insight", "extract_sales_dashboard_s2", {
        "signals": [
            {"kind": "stock_level", "sku": "SKU-117", "metric": "units_on_hand", "value": 180, "delta_vs_baseline_pct": 0.0, "rationale": "Sales dashboard registers 180 units."}
        ]
    })
    
    write_cache_file("S2", "insight", "extract_supplier_email_s2", {
        "signals": [
            {"kind": "stock_level", "sku": "SKU-117", "metric": "shipment_received", "value": 60, "delta_vs_baseline_pct": None, "rationale": "Email confirms 60 units received."}
        ]
    })
    
    write_cache_file("S2", "insight", "extract_news_spoofed_s2", {
        "signals": [
            {"kind": "stock_level", "sku": "SKU-117", "metric": "units_on_hand", "value": 12, "delta_vs_baseline_pct": -90.0, "rationale": "Crisis news claims stock depleted to 12."}
        ]
    })
    
    write_cache_file("S2", "insight", "extract_complaints_log_s2", {
        "signals": [
            {"kind": "complaint_cluster", "sku": "SKU-117", "metric": "complaint_count", "value": 18, "delta_vs_baseline_pct": None, "rationale": "18 complaints regarding delay."}
        ]
    })
    
    # S2 Conflict resolution
    write_cache_file("S2", "insight", "conflict", {
        "winning_signal_index": 1,
        "confidence": 0.52,
        "reason": "Chose sales dashboard/warehouse stock over crisis spoofing with low confidence due to stark conflict."
    })
    
    # S2 Impact
    write_cache_file("S2", "planner", "impact", {
        "stockout_risk_pct": 58,
        "revenue_at_risk_pkr": 1600000,
        "days_of_stock_remaining": 5,
        "customers_affected": 18,
        "primary_threat": "Conflict in stock intelligence for SKU-117 causing execution risk.",
        "urgency": "high"
    })
    
    # S2 Plan - Must start with investigate because of low confidence resolved signal (< 0.6)
    write_cache_file("S2", "planner", "plan", {
        "actions": [
            {
                "id": "act-1",
                "kind": "investigate",
                "params": {"sku": "SKU-117", "target": "stock_reconciliation"},
                "depends_on": [],
                "constraints_required": [],
                "rationale": "Investigate SKU-117 stock discrepancies due to low confidence signals.",
                "feasible": True,
                "estimated_cost_pkr": 0
            },
            {
                "id": "act-2",
                "kind": "validate",
                "params": {"sku": "SKU-117"},
                "depends_on": ["act-1"],
                "constraints_required": [],
                "rationale": "Validate physical inventory levels after discrepancy check.",
                "feasible": True,
                "estimated_cost_pkr": 0
            },
            {
                "id": "act-3",
                "kind": "notify",
                "params": {"recipients": ["procurement-team"], "message": "Discrepancy investigation started."},
                "depends_on": ["act-2"],
                "constraints_required": [],
                "rationale": "Notify team of investigation status.",
                "feasible": True,
                "estimated_cost_pkr": 0
            }
        ],
        "total_estimated_impact_pkr": 0,
        "executable": True,
        "plan_summary": "Initiate stock reconciliation investigate, validate physical stock levels, and notify team of discrepancy status."
    })
    
    # ── S3 MOCK RESPONSES ────────────────────────────────────────────────────
    
    write_cache_file("S3", "insight", "extract_khan_warehouse_s3", {
        "signals": [
            {"kind": "stock_level", "sku": "SKU-204", "metric": "units_on_hand", "value": 8, "delta_vs_baseline_pct": -60.0, "rationale": "Inventory is critical at 8 units."}
        ]
    })
    
    write_cache_file("S3", "insight", "extract_sales_dashboard_s3", {
        "signals": [
            {"kind": "sales_change", "sku": "SKU-204", "metric": "pending_orders_unshipped", "value": 34, "delta_vs_baseline_pct": None, "rationale": "34 unshipped orders."}
        ]
    })
    
    write_cache_file("S3", "insight", "extract_supplier_email_s3", {
        "signals": [
            {"kind": "supplier_status", "sku": None, "metric": "delay_days", "value": 5, "delta_vs_baseline_pct": None, "rationale": "Supplier Karachi Cool silent for 5 days."}
        ]
    })
    
    write_cache_file("S3", "insight", "extract_alt_supplier_s3", {
        "signals": [
            {"kind": "price_change", "sku": "SKU-204", "metric": "unit_cost_pkr", "value": 13440, "delta_vs_baseline_pct": 12.0, "rationale": "Alternative supplier charges 12% premium."}
        ]
    })
    
    write_cache_file("S3", "insight", "extract_complaints_log_s3", {
        "signals": [
            {"kind": "complaint_cluster", "sku": None, "metric": "complaint_count", "value": 11, "delta_vs_baseline_pct": None, "rationale": "11 complaints regarding delay."}
        ]
    })
    
    # S3 Impact
    write_cache_file("S3", "planner", "impact", {
        "stockout_risk_pct": 89,
        "revenue_at_risk_pkr": 4500000,
        "days_of_stock_remaining": 2,
        "customers_affected": 34,
        "primary_threat": "Critical stock depletion with primary supplier silent.",
        "urgency": "critical"
    })
    
    # S3 Plan - order Karachi Cool (first fails, then retries and succeeds, adjust_eta gets rolled back)
    write_cache_file("S3", "planner", "plan", {
        "actions": [
            {
                "id": "act-1",
                "kind": "validate",
                "params": {"sku": "SKU-204"},
                "depends_on": [],
                "constraints_required": [],
                "rationale": "Validate SKU-204 stock levels first.",
                "feasible": True,
                "estimated_cost_pkr": 0
            },
            {
                "id": "act-2",
                "kind": "order",
                "params": {"sku": "SKU-204", "quantity": 30, "supplier": "Karachi Cool Systems"},
                "depends_on": ["act-1"],
                "constraints_required": ["budget_pkr"],
                "rationale": "Order 30 units of SKU-204 from Karachi Cool.",
                "feasible": True,
                "estimated_cost_pkr": 360000
            },
            {
                "id": "act-3",
                "kind": "adjust_eta",
                "params": {"sku": "SKU-204", "days_to_add": 5},
                "depends_on": ["act-2"],
                "constraints_required": [],
                "rationale": "Adjust customer ETAs due to order delay/retry risk.",
                "feasible": True,
                "estimated_cost_pkr": 0
            }
        ],
        "total_estimated_impact_pkr": 360000,
        "executable": True,
        "plan_summary": "Order 30 units from Karachi Cool and temporarily adjust customer ETAs during the transition."
    })

if __name__ == "__main__":
    main()
