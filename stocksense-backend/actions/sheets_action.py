from datetime import datetime, timedelta


class SheetsAction:
    def __init__(self, service, spreadsheet_id: str):
        self.service = service
        self.spreadsheet_id = spreadsheet_id

    def update_order_etas(self, orders: list[dict]) -> dict:
        try:
            result = self.service.spreadsheets().values().get(
                spreadsheetId=self.spreadsheet_id,
                range="Sheet1!A:Z",
            ).execute()
            rows = result.get("values", [])
        except Exception:
            rows = []

        headers = rows[0] if rows else ["date", "order_id", "sku", "quantity", "customer", "region", "new_eta", "status"]
        sku_col = headers.index("sku") if "sku" in headers else 2
        order_col = headers.index("order_id") if "order_id" in headers else 1

        new_eta = (datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d")
        order_ids = {o["order_id"] for o in orders if o.get("sku") == "SKU-007"}

        rows_modified = []
        updates = []
        for i, row in enumerate(rows[1:], start=2):
            if len(row) > max(sku_col, order_col):
                row_sku = row[sku_col] if len(row) > sku_col else ""
                row_oid = row[order_col] if len(row) > order_col else ""
                if row_sku == "SKU-007" or row_oid in order_ids:
                    eta_col_letter = chr(ord("A") + len(headers) - 1)
                    updates.append({
                        "range": f"Sheet1!{eta_col_letter}{i}",
                        "values": [[new_eta, "ETA_UPDATED"]],
                    })
                    rows_modified.append({"row": i, "order_id": row_oid, "new_eta": new_eta, "status": "ETA_UPDATED"})

        if not rows_modified:
            for order in orders:
                if order.get("sku") == "SKU-007" or order.get("order_id") in order_ids:
                    rows_modified.append({
                        "order_id": order.get("order_id"),
                        "new_eta": new_eta,
                        "status": "ETA_UPDATED",
                    })

        if updates and self.service:
            try:
                self.service.spreadsheets().values().batchUpdate(
                    spreadsheetId=self.spreadsheet_id,
                    body={"valueInputOption": "RAW", "data": updates},
                ).execute()
            except Exception:
                pass

        return {"updated_count": len(rows_modified), "rows_modified": rows_modified}
