import json
import random
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
import requests
from bs4 import BeautifulSoup

DATA_DIR = Path(__file__).parent.parent / "data"


class IngestionAgent:
    def run(self) -> list[dict]:
        sources = []
        sources.append(self._load_inventory())
        sources.append(self._load_sales_orders())
        sources.append(self._load_supplier_quote())
        sources.append(self._load_dawn_news())
        sources.append(self._generate_realtime_feed())
        return sources

    def _load_inventory(self) -> dict:
        with open(DATA_DIR / "inventory_snapshot.json", "r") as f:
            data = json.load(f)
        print(f"AGENT LOG [Ingestion]: Loaded json_dashboard - {len(data['inventory'])} items")
        return {
            "source_id": "inventory_snapshot",
            "source_type": "json_dashboard",
            "content": data,
            "ingested_at": datetime.now().isoformat(),
        }

    def _load_sales_orders(self) -> dict:
        df = pd.read_csv(DATA_DIR / "sales_orders.csv")
        records = df.to_dict(orient="records")
        print(f"AGENT LOG [Ingestion]: Loaded csv - {len(records)} items")
        return {
            "source_id": "sales_orders",
            "source_type": "csv",
            "content": records,
            "ingested_at": datetime.now().isoformat(),
        }

    def _load_supplier_quote(self) -> dict:
        text = (DATA_DIR / "supplier_quote.txt").read_text()
        print(f"AGENT LOG [Ingestion]: Loaded text_document - 1 items")
        return {
            "source_id": "supplier_quote",
            "source_type": "text_document",
            "content": text,
            "ingested_at": datetime.now().isoformat(),
        }

    def _load_dawn_news(self) -> dict:
        articles = []
        try:
            resp = requests.get("https://www.dawn.com/business", timeout=10)
            soup = BeautifulSoup(resp.text, "html.parser")
            story_tags = soup.select("article.story") or soup.select(".story__content")
            if not story_tags:
                story_tags = soup.find_all("article")
            for tag in story_tags[:3]:
                title_el = tag.find(["h2", "h3", "h4"])
                para_el = tag.find("p")
                articles.append({
                    "title": title_el.get_text(strip=True) if title_el else "No title",
                    "summary": para_el.get_text(strip=True) if para_el else "No summary",
                })
            if not articles:
                raise ValueError("No articles parsed")
        except Exception as e:
            print(f"AGENT LOG [Ingestion]: Dawn fetch failed ({e}), using fallback headlines")
            articles = [
                {"title": "Pakistan trade deficit widens amid import surge", "summary": "Import costs up 15% YoY driven by electronics and machinery."},
                {"title": "Port congestion at Karachi delays electronics imports", "summary": "Shipping delays of 3-5 days reported at Port Qasim."},
                {"title": "PKR stabilizes as SBP holds interest rate", "summary": "State Bank holds rate at 22% amid inflation concerns."},
            ]
        print(f"AGENT LOG [Ingestion]: Loaded web_article - {len(articles)} items")
        return {
            "source_id": "dawn_news",
            "source_type": "web_article",
            "content": articles,
            "ingested_at": datetime.now().isoformat(),
        }

    def _generate_realtime_feed(self) -> dict:
        now = datetime.now()
        orders = []
        for i in range(5):
            orders.append({
                "order_id": f"RT-{1000 + i}",
                "sku": "SKU-007",
                "quantity": random.randint(70, 90),
                "timestamp": (now - timedelta(hours=i * 2)).isoformat(),
                "customer": random.choice(["Ahmed Khan", "Sara Malik", "Usman Ali", "Bilal Ahmed"]),
                "region": random.choice(["Karachi", "Lahore", "Islamabad", "Peshawar"]),
            })
        print(f"AGENT LOG [Ingestion]: Loaded realtime_feed - {len(orders)} items")
        return {
            "source_id": "realtime_feed",
            "source_type": "realtime_feed",
            "content": orders,
            "ingested_at": datetime.now().isoformat(),
        }
