import json
import os

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

from agents.ingestion_agent import IngestionAgent
from agents.preprocessing_agent import PreprocessingAgent
from agents.credibility_scorer import CredibilityScorer
from agents.contradiction_detector import ContradictionDetector
from agents.insight_engine import InsightEngine
from agents.decision_planner import DecisionPlanner
from agents.action_executor import ActionExecutor
from agents.outcome_reporter import OutcomeReporter
from config import SPREADSHEET_ID

TOKEN_PATH = "token.json"
SCOPES = [
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/spreadsheets",
]


def _load_google_services():
    gmail_service = None
    sheets_service = None
    if os.path.exists(TOKEN_PATH):
        try:
            creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
            gmail_service = build("gmail", "v1", credentials=creds)
            sheets_service = build("sheets", "v4", credentials=creds)
            print("PIPELINE: Google services loaded from token.json")
        except Exception as e:
            print(f"PIPELINE: Could not load Google services ({e}), running without Gmail/Sheets")
    else:
        print("PIPELINE: token.json not found, running without Gmail/Sheets (run auth_setup.py first)")
    return gmail_service, sheets_service


def run_full_pipeline() -> dict:
    print("\n" + "=" * 60)
    print("  STOCKSENSE PIPELINE STARTING")
    print("=" * 60 + "\n")

    gmail_service, sheets_service = _load_google_services()

    # Stage 1: Ingestion
    print("\n--- Stage 1: Ingestion ---")
    sources = IngestionAgent().run()

    # Stage 2: Preprocessing
    print("\n--- Stage 2: Preprocessing ---")
    cleaned_sources = PreprocessingAgent().run(sources)

    # Stage 3: Credibility Scoring
    print("\n--- Stage 3: Credibility Scoring ---")
    scored_sources = CredibilityScorer().run(cleaned_sources)

    # Stage 4: Contradiction Detection
    print("\n--- Stage 4: Contradiction Detection ---")
    conflict_events = ContradictionDetector().run(scored_sources)

    # Stage 5: Insight Generation
    print("\n--- Stage 5: Insight Engine (Gemini) ---")
    insights = InsightEngine().run(scored_sources, conflict_events)

    # Stage 6: Decision Planning
    print("\n--- Stage 6: Decision Planner ---")
    action_chain = DecisionPlanner().run(insights)

    # Stage 7: Action Execution
    print("\n--- Stage 7: Action Executor ---")
    execution_log = ActionExecutor().run(
        action_chain, conflict_events, insights, gmail_service, sheets_service, SPREADSHEET_ID
    )

    # Stage 8: Outcome Reporting
    print("\n--- Stage 8: Outcome Reporter ---")
    outcome = OutcomeReporter().run(insights, execution_log, conflict_events)

    print("\n" + "=" * 60)
    print("  === PIPELINE COMPLETE ===")
    print(f"  Run ID       : {outcome['run_id']}")
    print(f"  Stockout Risk: {outcome['before_state']['stockout_risk_pct']}% -> {outcome['after_state']['stockout_risk_pct']}%")
    print(f"  Stock Status : {outcome['after_state']['stock_status']}")
    print(f"  Orders Updated: {outcome['after_state']['open_orders_updated']}")
    print(f"  Total Latency: {outcome['cost_summary']['total_latency_ms']}ms")
    print(f"  Projected Impact: {outcome['projected_impact']}")
    print("=" * 60 + "\n")

    return outcome


if __name__ == "__main__":
    result = run_full_pipeline()
    print(json.dumps(result, indent=2, default=str))
