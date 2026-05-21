from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from pipeline import run_full_pipeline

app = FastAPI(title="StockSense API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_outcomes: dict = {}

SCENARIO_META = {
    "S1": {"name": "Demand Spike Detection", "sku": "SKU-007", "description": "Detects sudden demand surges and triggers procurement alerts"},
    "S2": {"name": "Stockout Risk & Emergency Order", "sku": "SKU-007", "description": "Full risk pipeline: conflict detection, insights, emergency order simulation"},
    "S3": {"name": "Supplier Risk Assessment", "sku": "SKU-007", "description": "Evaluates supplier price hikes and lead time risks"},
}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/run-pipeline")
def run_pipeline():
    outcome = run_full_pipeline()
    run_id = outcome["run_id"]
    _outcomes[run_id] = outcome
    return outcome


@app.post("/scenarios/{scenario_id}/run")
def run_scenario(scenario_id: str):
    meta = SCENARIO_META.get(scenario_id.upper())
    if not meta:
        raise HTTPException(status_code=404, detail=f"Scenario '{scenario_id}' not found. Valid: S1, S2, S3")
    outcome = run_full_pipeline()
    outcome["scenario_id"] = scenario_id.upper()
    outcome["scenario_name"] = meta["name"]
    outcome["scenario_description"] = meta["description"]
    run_id = outcome["run_id"]
    _outcomes[run_id] = outcome
    return outcome


@app.get("/scenarios")
def list_scenarios():
    return [{"scenario_id": k, **v} for k, v in SCENARIO_META.items()]


@app.get("/scenarios/{scenario_id}")
def get_scenario(scenario_id: str):
    meta = SCENARIO_META.get(scenario_id.upper())
    if not meta:
        raise HTTPException(status_code=404, detail=f"Scenario '{scenario_id}' not found")
    return {"scenario_id": scenario_id.upper(), **meta}


@app.get("/outcome/{run_id}")
def get_outcome(run_id: str):
    if run_id not in _outcomes:
        raise HTTPException(status_code=404, detail=f"Run ID '{run_id}' not found")
    return _outcomes[run_id]
