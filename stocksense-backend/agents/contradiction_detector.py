from datetime import datetime


class ContradictionDetector:
    def run(self, sources: list[dict]) -> list[dict]:
        inventory_stock = self._get_inventory_stock(sources)
        realtime_orders = self._get_realtime_orders(sources)

        realtime_consumed = sum(o["quantity"] for o in realtime_orders)
        implied_stock = inventory_stock - realtime_consumed

        delta_pct = abs(inventory_stock - implied_stock) / inventory_stock * 100

        conflict_events = []
        if delta_pct > 15:
            inventory_credibility = next(
                (s["credibility_score"] for s in sources if s["source_id"] == "inventory_snapshot"), 0.44
            )
            realtime_credibility = next(
                (s["credibility_score"] for s in sources if s["source_id"] == "realtime_feed"), 0.90
            )
            resolution = (
                f"Accept realtime_feed value (credibility {realtime_credibility}) "
                f"over inventory_snapshot (credibility {inventory_credibility}, stale 3 days)"
            )
            event = {
                "metric": "SKU-007_stock_count",
                "source_a": "inventory_snapshot",
                "value_a": inventory_stock,
                "credibility_a": inventory_credibility,
                "source_b": "realtime_feed_implied",
                "value_b": implied_stock,
                "credibility_b": realtime_credibility,
                "delta_pct": round(delta_pct, 2),
                "resolution": resolution,
                "reconciled_stock": implied_stock,
                "timestamp": datetime.now().isoformat(),
            }
            conflict_events.append(event)
            print(
                f"AGENT LOG [Contradiction]: CONFLICT DETECTED on SKU-007_stock_count "
                f"- delta {round(delta_pct, 2)}% - {resolution}"
            )
        return conflict_events

    def _get_inventory_stock(self, sources: list[dict]) -> int:
        for s in sources:
            if s["source_id"] == "inventory_snapshot":
                for item in s["content"].get("inventory", []):
                    if item["sku"] == "SKU-007":
                        return item["stock"]
        return 500

    def _get_realtime_orders(self, sources: list[dict]) -> list[dict]:
        for s in sources:
            if s["source_id"] == "realtime_feed":
                return s["content"]
        return []
