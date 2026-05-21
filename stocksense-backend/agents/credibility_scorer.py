BASE_SCORES = {
    "realtime_feed": 0.95,
    "web_article": 0.85,
    "text_document": 0.80,
    "csv": 0.75,
    "json_dashboard": 0.70,
}


class CredibilityScorer:
    def run(self, sources: list[dict]) -> list[dict]:
        scored = []
        for source in sources:
            source = dict(source)
            base = BASE_SCORES.get(source["source_type"], 0.50)
            freshness = source.get("freshness_score", 1.0)
            score = round(base * freshness, 4)
            flag = "LOW_CREDIBILITY" if score < 0.50 else "OK"
            source["credibility_score"] = score
            source["credibility_flag"] = flag
            print(f"AGENT LOG [Credibility]: {source['source_id']} scored {score} - {flag}")
            scored.append(source)
        return scored
