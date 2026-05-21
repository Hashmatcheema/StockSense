# StockSense — Autonomous Inventory Risk Agent

**Challenge:** Google Antigravity Build Challenge  
**Domain:** Supply-chain / inventory risk for SMBs  
**Mock Business:** Khan Traders, Lahore  
**Stack:** Flutter (Android) · FastAPI · Google ADK · Gemini 2.5 Flash · SQLite

---

## What It Does

StockSense is a mobile-first agentic system that watches for supply-chain risks and acts on them autonomously. The operator selects a scenario (or the background monitor triggers one automatically), and a five-agent crew runs end-to-end:

1. **Ingests** five heterogeneous data sources (CSV warehouse sheet, JSON sales export, plain-text supplier email, JSON complaints log, HTML news article)
2. **Extracts** typed signals and **resolves contradictions** across sources using credibility scoring
3. **Plans** a 3–5 step action chain as a directed acyclic graph (DAG) under explicit budget, lead-time, and rate-limit constraints
4. **Simulates** execution against an in-process sandbox with retry, substitution, and rollback on failure
5. **Streams** a live trace of every agent decision to the mobile client via Server-Sent Events
6. **Presents** a before/after business state diff with quantified impact (stockout risk %, revenue at risk PKR, customer ETAs shifted)

The system observes, reasons, decides, acts, evaluates, and adapts — it is not a summarizer, a rule engine, or a static dashboard.

---

## Google Antigravity Integration

Antigravity was the **primary build environment** for this project throughout all phases:

| Artefact type | Role in submission |
|---|---|
| **Workplan / Task plan** | Generated at project start; tracked all 21 implementation items across 2 phases |
| **Implementation plans** | Per-phase plan documents guiding every file change (`project_artifacts/implementation_plan.md`) |
| **Walkthrough** | Post-phase audit confirming each change was applied (`project_artifacts/walkthrough.md`) |
| **Agent traces / logs** | Full JSON trace exported per run via `GET /runs/{run_id}/export`; also downloadable from the Before/After screen |
| **Observation → decision chain** | Every agent decision recorded as a `TraceEvent` (agent name, input summary, output summary, latency, tokens, detail JSON) and streamed live to the mobile app |

All build artefacts are under `project_artifacts/`.

---

## Agentic Reasoning & Workflow

```
Operator selects scenario
        │
        ▼
POST /scenarios/{id}/run
        │
        ▼
┌───────────────────────────────────────────────┐
│              SupervisorAgent                  │
│  ┌──────────────────────────────────────────┐ │
│  │ 1. IngestionAgent                        │ │
│  │    • Loads 5 source files from config    │ │
│  │    • Filters stale (>14 days) sources    │ │
│  │    • Filters duplicate content hashes    │ │
│  │    • Assigns credibility priors by type  │ │
│  └──────────────┬───────────────────────────┘ │
│                 │ accepted SourceDocuments     │
│  ┌──────────────▼───────────────────────────┐ │
│  │ 2. InsightAgent                          │ │
│  │    • Extracts typed Signals via Gemini   │ │
│  │    • Groups signals by (kind, metric,    │ │
│  │      SKU); detects contradictions        │ │
│  │    • Resolves via recency × credibility  │ │
│  │    • Flags low-confidence signals (<0.6) │ │
│  └──────────────┬───────────────────────────┘ │
│                 │ ResolvedSignals              │
│  ┌──────────────▼───────────────────────────┐ │
│  │ 3. PlannerAgent                          │ │
│  │    • Generates 3–5 action DAG via Gemini │ │
│  │    • Enforces budget / lead-time /       │ │
│  │      rate-limit constraints              │ │
│  │    • Replaces violating actions or marks │ │
│  │      plan non-executable                 │ │
│  └──────────────┬───────────────────────────┘ │
│                 │ ActionPlan (DAG)             │
│  ┌──────────────▼───────────────────────────┐ │
│  │ 4. ExecutorAgent                         │ │
│  │    • Simulates each action in DAG order  │ │
│  │    • On failure: retry once → substitute │ │
│  │    • If terminal failure: rolls back all │ │
│  │      dependent successors already run    │ │
│  │    • Mutates in-process Sandbox          │ │
│  └──────────────┬───────────────────────────┘ │
│                 │ ExecutionResults             │
│  Supervisor aggregates stats, persists        │
│  snapshot, computes StateDiff                 │
└───────────────────────────────────────────────┘
        │
        ▼
Mobile: Before/After screen with full diff
```

Every step emits `TraceEvent` objects streamed live over SSE to the Flutter client.

---

## Three Acceptance Scenarios

| ID | Title | Key demonstration |
|---|---|---|
| **S1** | Supply Chain Disruption | Happy path — stale news article filtered out, valid signals resolved, order+notify actions executed successfully |
| **S2** | Contradicting Market Intelligence | Contradiction resolution — spoofed news source detected; agentic credibility scoring picks the correct signal; baseline accepts both uncritically |
| **S3** | Order Failure and Recovery | Robustness — supplier API call fails; executor retries once, substitutes, rolls back dependents; baseline has no recovery logic |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   FLUTTER MOBILE APP (Android)               │
│  Scenarios screen │ Live Run screen │ Before/After screen    │
└─────────────────────────────┬────────────────────────────────┘
                              │ REST + SSE
┌─────────────────────────────▼────────────────────────────────┐
│                  FASTAPI BACKEND (Python 3.11)                │
│                                                              │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │ Source          │  │ Agent Crew        │                  │
│  │ Connectors      │→ │ (Google ADK +     │                  │
│  │ CSV/JSON/HTML/  │  │  Gemini 2.5 Flash)│                  │
│  │ email/PDF       │  └────────┬─────────┘                  │
│  └─────────────────┘           │                             │
│                       ┌────────▼─────────┐                  │
│                       │ Simulation       │                  │
│                       │ Sandbox          │                  │
│                       │ (in-process)     │                  │
│                       └────────┬─────────┘                  │
│                       ┌────────▼─────────┐                  │
│                       │ Trace Logger     │→ SQLite           │
│                       │ (SSE broadcast)  │                  │
│                       └──────────────────┘                  │
│                                                              │
│  Routes: /scenarios  /runs  /monitor                         │
└──────────────────────────────────────────────────────────────┘
```

**Key files:**

| Path | Responsibility |
|---|---|
| `backend/app/agents/supervisor.py` | Pipeline orchestrator |
| `backend/app/agents/ingestion.py` | Source loading, staleness/dedup filtering |
| `backend/app/agents/insight.py` | Signal extraction + contradiction resolution |
| `backend/app/agents/planner.py` | Action DAG generation + constraint checking |
| `backend/app/agents/executor.py` | Sandbox simulation + retry/rollback |
| `backend/app/sandbox.py` | In-process `BusinessState` mutation + diff |
| `backend/app/trace_logger.py` | SSE stream with per-run replay-on-connect |
| `backend/app/schemas.py` | All Pydantic models (single source of truth) |
| `lib/screens/scenarios_screen.dart` | Scenario list + recent runs |
| `lib/screens/live_run_screen.dart` | Live SSE trace + Action DAG card |
| `lib/screens/before_after_screen.dart` | Metric diff grid + export |

---

## Data Schemas

All schemas are defined as Pydantic models in `backend/app/schemas.py`.

```python
# Source normalisation
SourceDocument(id, kind, fetched_at, content, credibility_prior, recency_days, filename, content_hash)

# Signal kinds: sales_change | stock_level | supplier_status | price_change | complaint_cluster | external_shock
Signal(id, kind, sku, metric, value, delta_vs_baseline_pct, source_doc_ids, extracted_at)
ResolvedSignal(…Signal, confidence, conflicting_signal_ids, resolution_reason, low_confidence)
ConflictReport(id, metric, sku, conflicting_signal_ids, winning_signal_id, resolution_reason, confidence)

# Action kinds: validate | notify | order | adjust_eta | schedule_monitor | investigate | rollback
Action(id, kind, params, depends_on, rationale, estimated_impact_pkr, customers_affected, urgency)
ActionPlan(id, actions, total_estimated_impact_pkr, constraint_violations, is_executable)

# Execution
ExecutionResult(action_id, status, state_diff, latency_ms, tokens_used, error)
# status: success | failed | retried | rolled_back

# Business state (sandbox)
BusinessState(inventory, customer_etas, supplier_status, notification_queue, open_orders,
              risk_metrics, validated_skus, investigations, scheduled_checks)
StateDiff(before, after, changes_summary)

# Trace
TraceEvent(id, run_id, agent_name, event_type, input_summary, output_summary, detail, latency_ms, tokens_used, timestamp)
```

---

## Tools and APIs

| Tool / API | Purpose |
|---|---|
| **Google ADK** | Agent framework; each agent extends `BaseAgent`, emits typed `TraceEvent`s |
| **Gemini 2.5 Flash** | LLM for signal extraction, contradiction resolution, action planning |
| **FastAPI** | Backend HTTP service; REST + SSE endpoints |
| **SQLite** | Persistence for runs, trace events, sandbox snapshots |
| **Flutter** | Cross-platform mobile UI (Android primary) |
| **Google Fonts (Inter + JetBrains Mono)** | UI typography |
| **share_plus / path_provider** | Trace JSON export via native share sheet |
| **shared_preferences** | Persistent API base URL override |

---

## Setup

### Prerequisites
- Python 3.11+
- Flutter SDK (stable channel)
- Android emulator or device
- Gemini API key

### Backend

```bash
cd stock_sense/backend
python -m venv venv
venv\Scripts\activate          # Windows
pip install -r requirements.txt
set GEMINI_API_KEY=your_key_here
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Mobile App

```bash
cd stock_sense
flutter pub get
# Emulator (default): connects to http://10.0.2.2:8000
flutter run

# Physical device: set API URL in app Settings screen, or pass at build time:
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

The API base URL can also be changed at runtime from the app's Settings screen without rebuilding.

---

## Assumptions

- **A-1.** All data is synthetic. `khan_warehouse_oct.csv`, `sales_dashboard_lahore.json`, etc. are fixture files under `scenarios/{S1,S2,S3}/`. No real business data is used.
- **A-2.** Gemini API is available and the key has sufficient quota (~1,200 tokens × 5 calls per run).
- **A-3.** The backend runs on the same LAN as the test device/emulator.
- **A-4.** Scenario S3 failure injection is deterministic: the executor simulates a supplier API failure on the first `order` action, then retries and substitutes.
- **A-5.** Offline/demo mode (`offline_mode: true` in `POST /scenarios/{id}/run`) uses pre-cached Gemini responses so the demo works without live API access.

---

## Privacy Note

No real personal data is collected or stored. All inventory figures, order IDs, customer names, and supplier communications are entirely synthetic. The SQLite database (`stocksense.db`) holds only agent trace logs and simulated business state. It is local to the developer machine and is not transmitted anywhere.

---

## Cost and Latency

All measurements on Windows 11, 16 GB RAM, using Gemini 2.5 Flash.

| Scenario | Avg tokens | Avg latency | Avg cost (USD) |
|---|---|---|---|
| S1 — Supply Chain Disruption | 1,247 | 12.1 s | $0.030 |
| S2 — Contradicting Intelligence | 1,158 | 10.5 s | $0.026 |
| S3 — Order Failure & Recovery | 1,205 | 11.5 s | $0.029 |

Token rate: $0.15 / 1M tokens (Gemini 2.5 Flash blended). All runs are well within the $0.20/run NFR with ~6× headroom. Full measurement methodology: [`docs/cost-latency.md`](docs/cost-latency.md).

---

## Baseline Comparison

A naive heuristic baseline processes one source at a time with fixed threshold rules — no LLM, no cross-source referencing, no constraint checking.

| Metric | S1 Agentic | S1 Baseline | S2 Agentic | S2 Baseline | S3 Agentic | S3 Baseline |
|---|---|---|---|---|---|---|
| Correct insight | Yes | Yes | **Yes** | **No** | **Yes** | **No** |
| Actions taken | 5 | 13 | 3 | 5 | 4 | 9 |
| Constraint violations | 0 | 8 | 0 | 0 | 0 | 4 |
| Recovered from failure | — | — | — | — | **Yes** | **No** |
| Latency (s) | 12.4 | 1.0 | 10.8 | 0.008 | 11.2 | 0.18 |
| Cost (USD) | $0.031 | $0.000 | $0.026 | $0.000 | $0.029 | $0.000 |

Key advantages of the agentic system:
- **Contradiction resolution (S2):** baseline accepts the spoofed news source as authoritative; agentic system detects the value divergence and selects the higher-credibility signal.
- **Failure recovery (S3):** baseline has no retry or rollback; agentic executor retries once, substitutes, and rolls back dependents.
- **Constraint enforcement:** baseline generates 8–13 unconstrained actions; agentic planner enforces budget, lead-time, and rate-limit constraints producing 3–5 valid steps.

Full comparison: [`docs/baseline.md`](docs/baseline.md).

---

## Robustness Evidence

Three robustness scenarios are demonstrated end-to-end in the app:

1. **Stale source rejection (S1):** `news_fuel_prices.html` has `recency_days: 18` in `config.yaml`; the Ingestion agent emits a `filtered_out` event and excludes it. The run still completes successfully on the remaining four sources.

2. **Contradicting source (S2):** Two sources report fuel price changes with >10% value divergence. The Insight agent emits a `conflict_resolved` event, picks the higher-credibility winner, and flags the plan with a human-readable resolution reason visible in the trace.

3. **Order failure + rollback (S3):** The Executor's first `order` action fails (simulated supplier API timeout). The agent retries once (status: `retried`), fails again, substitutes with an `investigate` action, then rolls back all dependent successors (status: `rolled_back`). The final state diff correctly excludes the failed order's impact.

---

## Scalability

**Current:** Single developer laptop. One run at a time. SQLite. ~12s end-to-end.

**10× scaling (10 concurrent runs):**
- FastAPI already runs with async I/O; multiple runs can be handled concurrently up to Gemini API rate limits.
- Replace SQLite with PostgreSQL; connection pooling with asyncpg.
- Estimated cost: $0.03 × 10 runs/min = $0.30/min ≈ $18/hour — well within API tier limits.
- Latency unchanged per run (Gemini call latency is the bottleneck, not I/O).

**100× scaling:**
- Deploy backend as a stateless service (Cloud Run or GKE).
- Use Pub/Sub for SSE fan-out instead of in-process asyncio queues.
- Gemini API batch quotas need to be negotiated; alternatively shard by scenario across multiple API keys.
- SQLite → PostgreSQL (managed, Cloud SQL).
- Estimated throughput: ~500 runs/hour with horizontal scaling.

---

## Limitations

- No real third-party API integration — all source data is file-based fixtures.
- No authentication or multi-tenancy — single-user local demo.
- No cloud deployment in v1 — local laptop only.
- Gemini response caching for offline mode covers the three acceptance scenarios only; novel scenarios require live API access.
- iOS support is best-effort; tested primarily on Android emulator.
- Monitor daemon polls on a fixed interval; no webhook-based push from real suppliers.
