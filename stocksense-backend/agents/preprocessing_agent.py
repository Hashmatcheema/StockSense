from datetime import datetime


FRESHNESS_MAP = {
    "realtime_feed": 0.95,
    "web_article": 0.85,
    "text_document": 0.80,
    "csv": 0.75,
}


class PreprocessingAgent:
    def run(self, sources: list[dict]) -> list[dict]:
        cleaned = []
        for source in sources:
            processed = self._clean_source(source)
            cleaned.append(processed)
        return cleaned

    def _clean_source(self, source: dict) -> dict:
        source = dict(source)
        stype = source["source_type"]

        if stype == "csv":
            source["content"], dups = self._dedup_orders(source["content"])
            items_before = len(source["content"]) + dups
            items_after = len(source["content"])
            print(f"AGENT LOG [Preprocessing]: {items_before} items -> {items_after} items, {dups} duplicates removed")
        else:
            print(f"AGENT LOG [Preprocessing]: source={source['source_id']} no dedup needed")

        source["content"] = self._strip_nones(source["content"])
        source["freshness_score"] = self._get_freshness(source)
        return source

    def _dedup_orders(self, records: list[dict]) -> tuple[list[dict], int]:
        seen = set()
        unique = []
        for row in records:
            oid = row.get("order_id")
            if oid not in seen:
                seen.add(oid)
                unique.append(row)
        return unique, len(records) - len(unique)

    def _strip_nones(self, content):
        if isinstance(content, list):
            return [{k: v for k, v in item.items() if v is not None} if isinstance(item, dict) else item for item in content]
        if isinstance(content, dict):
            return {k: v for k, v in content.items() if v is not None}
        return content

    def _get_freshness(self, source: dict) -> float:
        stype = source["source_type"]
        if stype in FRESHNESS_MAP:
            return FRESHNESS_MAP[stype]
        if stype == "json_dashboard":
            days_old = source["content"].get("snapshot_age_days", 0)
            return max(0.1, 1.0 - (days_old * 0.10))
        return 0.5
