class DecisionPlanner:
    BUDGET_LIMIT_PKR = 65000
    NOTIFICATION_DEADLINE_HOURS = 2
    MAX_ORDER_UPDATES_PER_BATCH = 10
    URGENCY_THRESHOLD_DAYS = 3

    UNIT_COST_SUPPLIER_A = 49
    UNIT_COST_SUPPLIER_B = 43

    def run(self, insights: dict) -> list[dict]:
        stockout_risk = insights.get("stockout_risk_pct", 0)
        days_of_cover = insights.get("days_of_cover", 99)
        recommended_qty = insights.get("recommended_order_qty", 1200)

        action_chain = []

        # A1: Always validate stock first
        action_chain.append({
            "action_id": "A1",
            "name": "validate_stock",
            "status": "APPROVED",
            "constraint_check": "Always required",
            "params": {"sku": "SKU-007"},
            "depends_on": None,
        })

        # A2: Alert procurement if stockout risk > 50%
        if stockout_risk > 50:
            action_chain.append({
                "action_id": "A2",
                "name": "alert_procurement",
                "status": "APPROVED",
                "constraint_check": f"stockout_risk={stockout_risk}% > 50% threshold",
                "params": {
                    "sku": "SKU-007",
                    "stockout_risk_pct": stockout_risk,
                    "days_of_cover": days_of_cover,
                },
                "depends_on": "A1",
            })

        # A3: Simulate emergency order if days_of_cover < URGENCY_THRESHOLD_DAYS
        if days_of_cover < self.URGENCY_THRESHOLD_DAYS:
            cost_a = recommended_qty * self.UNIT_COST_SUPPLIER_A
            if cost_a <= self.BUDGET_LIMIT_PKR:
                a3_status = "APPROVED"
                supplier = "Supplier A (Shenzhen Electronics Co.)"
                unit_price = self.UNIT_COST_SUPPLIER_A
                qty = recommended_qty
                total_cost = cost_a
                constraint_note = f"Cost PKR {cost_a} <= budget PKR {self.BUDGET_LIMIT_PKR}"
            else:
                # Try fallback qty=1500 -> over budget, try Supplier B
                cost_b = recommended_qty * self.UNIT_COST_SUPPLIER_B
                if cost_b <= self.BUDGET_LIMIT_PKR:
                    a3_status = "APPROVED"
                    supplier = "Supplier B (Fallback)"
                    unit_price = self.UNIT_COST_SUPPLIER_B
                    qty = recommended_qty
                    total_cost = cost_b
                    constraint_note = f"Supplier A cost PKR {cost_a} > budget; Supplier B cost PKR {cost_b} approved"
                else:
                    a3_status = "REJECTED"
                    supplier = "None"
                    unit_price = 0
                    qty = 0
                    total_cost = 0
                    constraint_note = f"Both suppliers exceed budget PKR {self.BUDGET_LIMIT_PKR}"

            action_chain.append({
                "action_id": "A3",
                "name": "simulate_emergency_order",
                "status": a3_status,
                "constraint_check": constraint_note,
                "params": {
                    "supplier": supplier,
                    "sku": "SKU-007",
                    "qty": qty,
                    "unit_price": unit_price,
                    "total_cost": total_cost,
                },
                "depends_on": "A2",
            })

        # A4: Update delivery ETAs after order placed
        action_chain.append({
            "action_id": "A4",
            "name": "update_delivery_etas",
            "status": "APPROVED",
            "constraint_check": f"Batch size <= {self.MAX_ORDER_UPDATES_PER_BATCH}",
            "params": {"sku": "SKU-007", "batch_size": self.MAX_ORDER_UPDATES_PER_BATCH},
            "depends_on": "A3",
        })

        # A5: Always schedule monitoring last
        action_chain.append({
            "action_id": "A5",
            "name": "schedule_monitoring",
            "status": "APPROVED",
            "constraint_check": "Always required",
            "params": {"interval_hours": 6, "alert_threshold_units": 50},
            "depends_on": None,
        })

        approved = sum(1 for a in action_chain if a["status"] == "APPROVED")
        rejected = sum(1 for a in action_chain if a["status"] == "REJECTED")
        names = [a["name"] for a in action_chain]
        print(f"AGENT LOG [Planner]: {approved} actions approved, {rejected} rejected. Chain: {names}")
        return action_chain
