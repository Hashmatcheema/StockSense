import time
from datetime import datetime, timedelta

from actions.gmail_action import GmailAction
from actions.sheets_action import SheetsAction


class ActionExecutor:
    def __init__(self):
        self._reconciled_stock = None

    def run(
        self,
        action_chain: list[dict],
        conflict_events: list[dict],
        insights: dict,
        gmail_service,
        sheets_service,
        spreadsheet_id: str,
    ) -> list[dict]:
        self._reconciled_stock = self._get_reconciled_stock(conflict_events)
        execution_log = []

        for action in action_chain:
            if action["status"] == "REJECTED":
                execution_log.append({
                    "action_id": action["action_id"],
                    "name": action["name"],
                    "status": "SKIPPED_REJECTED",
                    "state_before": {},
                    "state_after": {},
                    "latency_ms": 0,
                })
                print(f"AGENT LOG [Executor]: {action['action_id']} {action['name']} -> SKIPPED_REJECTED (0ms)")
                continue

            start = time.time()
            state_before = {"timestamp": datetime.now().isoformat()}
            result = {}
            status = "SUCCESS"

            try:
                if action["action_id"] == "A1":
                    result = self._validate_stock()
                elif action["action_id"] == "A2":
                    result = self._alert_procurement(action, insights, gmail_service)
                elif action["action_id"] == "A3":
                    result = self._simulate_emergency_order(action)
                elif action["action_id"] == "A4":
                    result = self._update_delivery_etas(action, sheets_service, spreadsheet_id)
                elif action["action_id"] == "A5":
                    result = self._schedule_monitoring(action)
            except Exception as e:
                status = "FAILED"
                result = {"error": str(e)}

            latency_ms = round((time.time() - start) * 1000)
            state_after = {**result, "timestamp": datetime.now().isoformat()}

            log_entry = {
                "action_id": action["action_id"],
                "name": action["name"],
                "status": status,
                "state_before": state_before,
                "state_after": state_after,
                "latency_ms": latency_ms,
            }
            execution_log.append(log_entry)
            print(f"AGENT LOG [Executor]: {action['action_id']} {action['name']} -> {status} ({latency_ms}ms)")

        return execution_log

    def _get_reconciled_stock(self, conflict_events: list[dict]) -> int:
        for event in conflict_events:
            if "reconciled_stock" in event:
                return event["reconciled_stock"]
        return 500

    def _validate_stock(self) -> dict:
        stock = self._reconciled_stock
        status = "CRITICAL" if stock < 200 else "WARNING" if stock < 300 else "OK"
        return {"reconciled_stock": stock, "stock_status": f"VERIFIED_{status}"}

    def _alert_procurement(self, action: dict, insights: dict, gmail_service) -> dict:
        params = action["params"]
        sku = params.get("sku", "SKU-007")
        days_cover = insights.get("days_of_cover", 2.3)
        order_qty = insights.get("recommended_order_qty", 1200)
        stock = self._reconciled_stock

        if gmail_service is None:
            return self._create_email_draft(sku, stock, days_cover, order_qty)

        gmail = GmailAction(gmail_service)
        try:
            result = gmail.send_procurement_alert(sku, stock, days_cover, order_qty)
            return {"procurement_status": "ALERTED", **result}
        except Exception:
            try:
                result = gmail.send_procurement_alert(sku, stock, days_cover, order_qty)
                return {"procurement_status": "ALERTED", **result}
            except Exception as e2:
                return {**self._create_email_draft(sku, stock, days_cover, order_qty), "retry_error": str(e2)}

    def _create_email_draft(self, sku: str, stock: int, days_cover: float, order_qty: int) -> dict:
        return {
            "procurement_status": "FALLBACK_EMAIL_DRAFT",
            "draft": {
                "subject": f"URGENT STOCKOUT ALERT - {sku} | StockSense",
                "body": (
                    f"URGENT: {sku} stock at {stock} units (~{days_cover} days cover). "
                    f"Recommend emergency order of {order_qty} units immediately."
                ),
                "to": "procurement@company.com",
            },
        }

    def _simulate_emergency_order(self, action: dict) -> dict:
        params = action["params"]
        total_cost = params["total_cost"]
        budget = 65000
        order_status = "APPROVED" if total_cost <= budget else "REJECTED_OVER_BUDGET"
        return {
            "order": {
                "supplier": params["supplier"],
                "sku": params["sku"],
                "qty": params["qty"],
                "unit_price": params["unit_price"],
                "total_cost": total_cost,
                "status": order_status,
            }
        }

    def _update_delivery_etas(self, action: dict, sheets_service, spreadsheet_id: str) -> dict:
        if sheets_service is None:
            orders = [{"order_id": f"ORD-{i:03d}", "sku": "SKU-007"} for i in range(16, 21)]
            updated = []
            for i, order in enumerate(orders):
                new_eta = (datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d")
                updated.append({"order_id": order["order_id"], "new_eta": new_eta, "status": "ETA_UPDATED"})
            return {"updated_count": len(updated), "rows_modified": updated}

        sheets = SheetsAction(sheets_service, spreadsheet_id)
        batch_size = action["params"].get("batch_size", 10)
        orders = [{"order_id": f"ORD-{i:03d}", "sku": "SKU-007"} for i in range(16, 21)]

        all_updated = []
        for i in range(0, len(orders), batch_size):
            batch = orders[i : i + batch_size]
            result = sheets.update_order_etas(batch)
            all_updated.extend(result.get("rows_modified", []))

        return {"updated_count": len(all_updated), "rows_modified": all_updated}

    def _schedule_monitoring(self, action: dict) -> dict:
        params = action["params"]
        next_run = (datetime.now() + timedelta(hours=params["interval_hours"])).isoformat()
        return {
            "monitoring_job": {
                "interval_hours": params["interval_hours"],
                "alert_threshold_units": params["alert_threshold_units"],
                "sku": "SKU-007",
                "next_run": next_run,
                "status": "SCHEDULED",
            }
        }
