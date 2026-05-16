# Software Requirements Specification
## StockSense — Autonomous Content-to-Action Agent

| Field | Value |
|---|---|
| Document type | Software Requirements Specification (SRS) |
| Project | StockSense |
| Version | 2.0 |
| Status | Approved for development |
| Standard reference | IEEE 830 (adapted) |

---

## 1. Introduction

### 1.1 Purpose
This document specifies the software requirements for **StockSense**, a mobile-first agentic system that ingests multi-source unstructured business content, extracts insights, resolves contradictions, generates a constrained 3–5 step action chain, simulates execution, and visualises before/after business state.

### 1.2 Scope
StockSense covers the inventory and supply-chain risk domain for a single mock SMB ("Khan Traders, Lahore"). The system shall accept five distinct source types per scenario, run a five-agent crew, simulate a chain of actions against an in-process sandbox, and present a streamed trace and before/after diff to the user on Android.

Out of scope: real third-party API integration, multi-tenancy, authentication, cloud deployment, web administration UI, handling of real personal data.

### 1.3 Definitions and Acronyms
| Term | Definition |
|---|---|
| ADK | Google Agent Development Kit |
| Action chain | A 3–5 step directed acyclic graph (DAG) of typed actions |
| Antigravity | Google's agent-first IDE used as the build environment |
| Increment | A self-contained development unit that produces a demoable state |
| LLM | Large Language Model (Gemini 3 Pro / Gemini 3 Flash) |
| MUST/SHALL | Mandatory requirement |
| SHOULD | Strongly recommended requirement |
| MAY | Optional requirement |
| Sandbox | In-process mock of the business state |
| SDLC | Software Development Life Cycle |
| Signal | A typed, quantified observation extracted from a source |
| SRS | Software Requirements Specification |
| SSE | Server-Sent Events |

### 1.4 References
- Google Antigravity Build Challenge, Challenge Overview (Google, 2026).
- Google Antigravity Shared Submission Checklist (Google, 2026).
- IEEE Std 830-1998: IEEE Recommended Practice for Software Requirements Specifications.

### 1.5 Document Overview
Sections 2–7 specify the product, its functional requirements, non-functional requirements, data, and external interfaces. Section 8 declares the development methodology. Section 9 specifies the four development phases with entry and exit criteria. Section 10 specifies acceptance test cases. Section 11 lists deliverables. Section 12 is a glossary.

---

## 2. Overall Description

### 2.1 Product Perspective
StockSense is a self-contained mobile application backed by a local HTTP service. The agentic logic is implemented as a coordinated multi-agent system using Google ADK and Gemini. The application is constructed in its entirety inside Google Antigravity, which serves as the build environment and the source of submission artefacts (plan documents, walkthroughs, and execution traces).

### 2.2 Product Functions
At the highest level, StockSense shall:
- F-1. Ingest at least five heterogeneous data sources per scenario.
- F-2. Extract typed signals and resolve contradictions across sources.
- F-3. Generate a 3–5 step action chain under explicit constraints.
- F-4. Simulate execution of the action chain with state mutation.
- F-5. Recover from action failures via retry, substitution, or rollback.
- F-6. Stream a traceable record of all agent decisions to the mobile client.
- F-7. Present before/after business state with quantified impact.

### 2.3 User Characteristics
The system has a single user role: **Operator** (the SMB owner persona). The operator is assumed to have basic smartphone literacy. No training is required to use the application.

### 2.4 Constraints
- C-1. Build window: 5 calendar days.
- C-2. Team size: 2 developers.
- C-3. Build environment: Google Antigravity (mandatory).
- C-4. Runtime agent framework: Google ADK + Gemini (mandatory).
- C-5. Mobile platform: Flutter (Android primary, iOS best-effort).
- C-6. Backend platform: Python 3.11, FastAPI.
- C-7. Deployment target: local laptop with sideloaded APK; no cloud deployment in v1.
- C-8. All data must be synthetic. No real personal data.
- C-9. The system must operate within Gemini API rate limits available to a free or preview-tier account.

### 2.5 Assumptions and Dependencies
- A-1. Gemini 3 Pro and Gemini 3 Flash remain available throughout the build window.
- A-2. Google Antigravity remains in functional public preview throughout the build window.
- A-3. The development machine has stable internet for LLM calls.
- A-4. Android device or emulator available for sideload testing.

---

## 3. System Architecture

### 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       FLUTTER MOBILE APP                                │
│  Scenarios screen │ Live Run screen │ Before/After screen               │
└──────────────────┬──────────────────────────────────────────────────────┘
                   │ REST + Server-Sent Events (streamed trace)
┌──────────────────▼──────────────────────────────────────────────────────┐
│                    FASTAPI BACKEND (Python 3.11)                        │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────────────┐   │
│  │  Source        │  │  Agent Crew    │  │  Simulation Sandbox      │   │
│  │  Connectors    │──▶  (Google ADK   │──▶  (mock APIs, state DB)   │   │
│  │  (PDF/CSV/...) │  │   + Gemini 3)  │  │                          │   │
│  └────────────────┘  └────────┬───────┘  └──────────────────────────┘   │
│                               │                                          │
│                       ┌───────▼────────┐                                 │
│                       │  Trace Logger  │  → persisted to SQLite         │
│                       └────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Decomposition

| Component | Responsibility |
|---|---|
| Mobile client | Renders state and trace. No business logic. |
| HTTP service | Stateless orchestrator. Loads scenarios, invokes the agent crew, persists traces, streams events. |
| Source connectors | Five typed adapters that normalise raw files into `SourceDocument`. |
| Agent crew | Five specialist agents and one supervisor (see §4). |
| Simulation sandbox | In-process and SQLite-backed mock of the business state. Every action mutates this sandbox; no external mutations occur. |
| Trace logger | Structured JSON-lines log of every agent decision, streamed via SSE to the client. |
| Scenario loader | Loads deterministic source-file fixtures for the three acceptance scenarios. |

### 3.3 Data Flow
1. Operator selects a scenario from the Scenarios screen.
2. Mobile client issues `POST /scenarios/{id}/run` and opens an SSE subscription on `/runs/{run_id}/events`.
3. Backend loads scenario fixtures, invokes the Supervisor.
4. Supervisor dispatches to Ingestion → Insight → Planner → Executor in sequence; each agent emits trace events.
5. Executor mutates the sandbox; mobile receives the final state diff via `/runs/{run_id}/state-diff`.

---

## 4. Functional Requirements

### 4.1 Source Ingestion (Ingestion Agent)
- **FR-1.1** The system shall accept at least five distinct source types per scenario: PDF report, CSV file, JSON file, plain-text email/WhatsApp message, and HTML news article.
- **FR-1.2** The system shall normalise each source to a `SourceDocument` object containing kind, fetched-at timestamp, content, credibility prior (0–1), and recency in days.
- **FR-1.3** The system shall reject sources older than a configurable staleness threshold (default: 14 days) and emit a `filtered_out` event explaining the rejection.
- **FR-1.4** The system shall reject duplicate sources (matching by content hash) and emit a `filtered_out` event.
- **FR-1.5** The system shall assign each source-type a credibility prior in [0, 1].

### 4.2 Insight Extraction and Contradiction Resolution (Insight Agent)
- **FR-2.1** The system shall extract zero or more typed `Signal` objects from each accepted source.
- **FR-2.2** A signal shall contain at minimum: kind, optional SKU, metric name, numeric value, delta-vs-baseline percentage, source-document IDs, and extracted-at timestamp.
- **FR-2.3** Signal kinds shall be a closed set: `sales_change`, `stock_level`, `supplier_status`, `price_change`, `complaint_cluster`, `external_shock`.
- **FR-2.4** When two or more signals concerning the same metric and SKU disagree, the system shall produce a `ConflictReport` and select one winning signal based on a credibility score (recency × source-type prior).
- **FR-2.5** Each resolved signal shall carry a confidence score in [0, 1] and a human-readable resolution reason.
- **FR-2.6** When the resolved confidence falls below 0.6, the system shall flag the signal as low-confidence so that the Planner may insert an `investigate` action.

### 4.3 Action Planning and Constraint Checking (Planner Agent)
- **FR-3.1** The system shall produce an action plan containing between 3 and 5 actions per scenario.
- **FR-3.2** Each action shall be of a closed kind: `validate`, `notify`, `order`, `adjust_eta`, `schedule_monitor`, `investigate`, `rollback`.
- **FR-3.3** The action plan shall be representable as a directed acyclic graph with explicit `depends_on` relations.
- **FR-3.4** The Planner shall estimate business impact in PKR, customers affected, and urgency (low/medium/high/critical) for each input signal.
- **FR-3.5** The system shall enforce the following constraint classes against the plan: budget (PKR maximum), lead-time (days), urgency, and rate-limit (max actions per minute).
- **FR-3.6** When an action violates a constraint, the system shall either replace it with a feasible alternative or annotate the plan with the violation reason. Plans containing unresolvable violations shall not be executed.
- **FR-3.7** Each action shall include a `rationale` string explaining why it was selected.

### 4.4 Action Execution and Recovery (Executor Agent)
- **FR-4.1** The system shall simulate every action against the sandbox and emit an `ExecutionResult` per action containing status, state diff, latency, tokens used, and optional error.
- **FR-4.2** Execution status shall be one of: `success`, `failed`, `retried`, `rolled_back`.
- **FR-4.3** On action failure, the system shall retry the same action at most once with the same parameters.
- **FR-4.4** If the retry fails, the system shall attempt one substitution (a functionally equivalent action) before declaring the action failed.
- **FR-4.5** When an action that has dependent successors fails terminally, the system shall roll back the state diffs of all successor actions that have already executed.
- **FR-4.6** The system shall preserve the pre-run sandbox snapshot so that a full rollback to the initial state is always possible.

### 4.5 Trace Logging and Streaming (Supervisor + Trace Logger)
- **FR-5.1** The system shall persist every agent invocation to a structured trace log containing agent name, input summary, output summary, latency, and token cost.
- **FR-5.2** The system shall stream trace events to subscribed clients via Server-Sent Events within 300 ms of generation.
- **FR-5.3** The system shall expose the full trace of a completed run via `GET /runs/{run_id}`.

### 4.6 Mobile Application
- **FR-6.1** The mobile app shall present a Scenarios screen listing the three acceptance scenarios.
- **FR-6.2** The mobile app shall present a Live Run screen rendering streamed agent trace events as they arrive and the action DAG once the Planner emits it.
- **FR-6.3** The mobile app shall present a Before/After screen showing diffs in inventory units, customer ETAs, supplier status, stockout-risk percentage, and revenue-at-risk in PKR.
- **FR-6.4** Each trace-event row shall be expandable to reveal the full input/output JSON for that agent step.
- **FR-6.5** The mobile app shall display live token cost and cumulative latency during a run.
- **FR-6.6** The mobile app shall support exporting the trace log of any completed run as a JSON file.

### 4.7 Baseline Comparison
- **FR-7.1** The system shall include a naive reactive heuristic baseline implementation that processes one source at a time without cross-referencing.
- **FR-7.2** The system shall provide a benchmark script that runs both the agentic system and the baseline against the three acceptance scenarios and produces a comparison table.
- **FR-7.3** The comparison table shall report: correct insight (boolean), actions taken count, constraint violations count, recovery from failure (boolean), latency, and cost per run.

---

## 5. Non-Functional Requirements

### 5.1 Performance
- **NFR-1.1** A full scenario run shall complete in ≤ 20 seconds wall-clock under nominal Gemini API conditions.
- **NFR-1.2** Trace events shall be streamed to the mobile client within 300 ms of generation.
- **NFR-1.3** Mobile cold start to Scenarios screen shall be ≤ 2 seconds.
- **NFR-1.4** Trace-event rendering on mobile shall complete within 200 ms of arrival.

### 5.2 Reliability
- **NFR-2.1** All three acceptance scenarios shall execute deterministically (same final state within a documented tolerance) across consecutive runs.
- **NFR-2.2** The system shall handle a Gemini API timeout in any agent call without aborting the run, surfacing the failure to the trace and continuing where possible.
- **NFR-2.3** The system shall include pre-cached LLM responses for the three acceptance scenarios so that offline demonstration is possible.

### 5.3 Usability
- **NFR-3.1** The mobile UI shall be operable without prior training.
- **NFR-3.2** The Before/After diff shall use colour and magnitude to make the dominant change visible within three seconds of screen entry.
- **NFR-3.3** The mobile app shall not present a free-form chat interface.

### 5.4 Maintainability
- **NFR-4.1** All agent input and output types shall be defined as Pydantic models in a single shared module.
- **NFR-4.2** Scenario fixtures shall be expressed as files under `/scenarios/{scenario_id}/` so that adding a scenario requires no code changes outside that directory.
- **NFR-4.3** The action taxonomy shall be a closed enumeration; adding an action kind requires explicit code change in both Planner and Executor.

### 5.5 Cost and Resource
- **NFR-5.1** Average Gemini token cost per scenario run shall not exceed USD 0.20.
- **NFR-5.2** The backend shall run on a standard developer laptop (8 GB RAM minimum) without GPU.
- **NFR-5.3** SQLite shall be the only persistence dependency in v1.

### 5.6 Traceability and Auditability
- **NFR-6.1** Every agent decision shall be reconstructable from the persisted trace log.
- **NFR-6.2** Every action's state mutation shall be recorded as a diff against the prior state.
- **NFR-6.3** Antigravity build artefacts (Plan documents, Implementation Plans, Walkthroughs) shall be exported to `/antigravity-artifacts/` in the repository at the end of each development phase.

---

## 6. Data Requirements

### 6.1 Data Sources
The system shall ingest the following source types per scenario:

| ID | Type | Format | Example filename |
|---|---|---|---|
| DS-1 | Warehouse stock sheet | CSV | `khan_warehouse_oct.csv` |
| DS-2 | Sales dashboard export | JSON | `sales_dashboard_lahore.json` |
| DS-3 | Supplier communication | Plain text | `supplier_email_karachi_cool.txt` |
| DS-4 | Customer complaints log | JSON | `complaints_log_oct.json` |
| DS-5 | News article | HTML | `news_fuel_prices.html` |

### 6.2 Core Data Schemas

```python
class SourceDocument(BaseModel):
    id: str
    kind: Literal["pdf", "csv", "json", "email", "news_html"]
    fetched_at: datetime
    content: str | dict | list
    credibility_prior: float          # 0..1
    recency_days: float

class Signal(BaseModel):
    id: str
    kind: Literal["sales_change", "stock_level", "supplier_status",
                  "price_change", "complaint_cluster", "external_shock"]
    sku: str | None
    metric: str
    value: float
    delta_vs_baseline_pct: float | None
    source_doc_ids: list[str]
    extracted_at: datetime

class ResolvedSignal(Signal):
    confidence: float                  # 0..1
    conflicting_signal_ids: list[str]
    resolution_reason: str

class Action(BaseModel):
    id: str
    kind: Literal["validate", "notify", "order", "adjust_eta",
                  "schedule_monitor", "investigate", "rollback"]
    params: dict
    depends_on: list[str]
    constraints_required: list[str]
    rationale: str

class ExecutionResult(BaseModel):
    action_id: str
    status: Literal["success", "failed", "retried", "rolled_back"]
    state_diff: dict
    latency_ms: int
    tokens_used: int
    error: str | None
```

### 6.3 Sandbox State Schema

```python
class BusinessState(BaseModel):
    inventory: dict[str, int]                   # sku -> units
    customer_etas: dict[str, date]              # order_id -> promised date
    supplier_status: dict[str, str]             # supplier -> "active"|"delayed"|"silent"
    notification_queue: list[dict]
    open_orders: list[dict]
    risk_metrics: dict                          # stockout_risk_pct, revenue_at_risk_pkr
```

### 6.4 Reference Business Data (Mock)

```yaml
business:
  name: "Khan Traders"
  location: "Lahore, Pakistan"
  category: "Electronics & Home Appliances Wholesale"
  monthly_revenue_pkr: 12_500_000
  active_skus: 47
  cities_served: ["Lahore", "Faisalabad", "Multan", "Gujranwala"]
```

---

## 7. External Interface Requirements

### 7.1 User Interfaces
Three screens as specified in §4.6: Scenarios, Live Run, Before/After.

### 7.2 Software Interfaces

| Interface | Direction | Purpose |
|---|---|---|
| Gemini 3 Pro API (via ADK) | Outbound | LLM reasoning for Insight, Planner agents |
| Gemini 3 Flash API (via ADK) | Outbound | Lighter calls in Ingestion, Supervisor |
| Mock supplier API (in-process) | Internal | Simulated procurement endpoint, configurable failure rate |
| Mock notification queue (in-process) | Internal | Simulated stakeholder notifications |
| SQLite | Internal | Trace persistence, scenario state |

### 7.3 HTTP API

```
POST  /scenarios/{id}/run        → starts a scenario; returns run_id
GET   /runs/{run_id}             → final state + trace summary
GET   /runs/{run_id}/events      → SSE stream of agent events
GET   /runs/{run_id}/state-diff  → before vs after diff
GET   /runs/{run_id}/export      → full trace as JSON file
```

### 7.4 Build Environment Interface
- Google Antigravity (preview build) shall be the IDE used by both developers throughout all phases.
- All code changes shall originate from Antigravity tasks. Direct edits in other editors are not permitted during the build window.
- Antigravity Plan documents, Implementation Plans, and Walkthroughs shall be exported as build artefacts.

---

## 8. Development Methodology

### 8.1 Chosen Approach: Incremental SDLC
Development shall follow an **incremental** approach: the system is decomposed into self-contained increments, each producing a demonstrable, releasable state. Iterative refinement (prompt tuning, UI polish, edge-case fixes) is permitted **within** an increment but is bounded by that increment's exit criteria.

Each increment ends with:
1. A runnable state that can be demonstrated.
2. Exported Antigravity artefacts.
3. A committed and tagged Git state.

### 8.2 Roles
- **Developer A — Backend and Agents.** Owns FastAPI service, agent crew, ADK integration, scenario fixtures, sandbox.
- **Developer B — Mobile and UX.** Owns Flutter application, trace UI, before/after visualisation, video recording.

### 8.3 Daily Cadence
Each development day shall end with:
1. Commit and tag the day's state.
2. Push the Antigravity Plan document for the following day.
3. Run the latest acceptance test suite end-to-end.
4. Update Section 11 (Deliverables Checklist).

---

## 9. Development Phases

Four sequential phases. A phase shall not begin until the prior phase's exit criteria are satisfied. Each phase has acceptance gates verifiable by an objective observer.

### Phase 1 — Foundation and Walking Skeleton (Day 1)

**Objective:** Deliver an end-to-end skeleton in which the mobile client triggers a backend run, receives streamed events, and renders them. No real LLM calls.

**Entry criteria**
- Empty Git repository created.
- Antigravity installed on both developer machines.
- Gemini API credentials configured in both environments.

**Developer A tasks**
- 1.A.1 Scaffold FastAPI project (Python 3.11).
- 1.A.2 Implement SQLite schema for runs, trace events, sandbox snapshots.
- 1.A.3 Implement SSE endpoint at `GET /runs/{run_id}/events`.
- 1.A.4 Implement scenario-loader stub that returns hard-coded fake events.
- 1.A.5 Configure Google ADK with Gemini credentials; verify a `hello` call succeeds.
- 1.A.6 Define all Pydantic schemas in §6.2.

**Developer B tasks**
- 1.B.1 Scaffold Flutter project (Android target).
- 1.B.2 Implement Scenarios screen with three hard-coded scenario tiles.
- 1.B.3 Implement Live Run screen skeleton that opens an SSE connection and renders incoming events as list rows.
- 1.B.4 Implement Before/After screen skeleton with placeholder data bindings.

**Exit criteria**
- E-1.1 Tapping a scenario on mobile triggers a backend run.
- E-1.2 At least three fake events appear on the Live Run screen within five seconds of the tap.
- E-1.3 Both developers have committed at least one Antigravity Plan document to `/antigravity-artifacts/plans/`.
- E-1.4 All schemas in §6.2 are importable and lint-clean.

---

### Phase 2 — Agent Crew Implementation (Days 2–3)

**Objective:** Replace stubs with real agent implementations and complete Scenario S1 (happy path) end-to-end with real Gemini calls.

**Entry criteria**
- Phase 1 exit criteria all green.
- Scenario S1 source fixtures committed under `/scenarios/S1/`.

**Day 2 increments**
- 2.A.1 Ingestion Agent (FR-1.1 to FR-1.5). Implements the five source-type connectors and normalisation.
- 2.A.2 Insight Agent (FR-2.1 to FR-2.6). Includes contradiction resolution as a structured-output sub-step.
- 2.A.3 Planner Agent (FR-3.1 to FR-3.7). Includes constraint checking as a sub-step.
- 2.B.1 Live Run screen renders real agent rows with expandable JSON.
- 2.B.2 Live Run screen renders action DAG (read-only) once the Planner emits its plan.

**Day 3 increments**
- 3.A.1 Executor Agent (FR-4.1 to FR-4.6). Includes retry, substitution, and rollback logic.
- 3.A.2 Supervisor — wires all agents in sequence, emits final report.
- 3.A.3 Sandbox state mutation + diff generation (FR-4.1, NFR-6.2).
- 3.B.1 Before/After screen consumes real state diff. Risk metrics shall move visibly.
- 3.B.2 Live token cost and latency counters on Live Run screen (FR-6.5).

**Exit criteria**
- E-2.1 Scenario S1 runs end-to-end with real Gemini calls in ≤ 20 seconds (NFR-1.1).
- E-2.2 At least one contradiction is resolved during S1 and logged in the trace (FR-2.4).
- E-2.3 A 3–5 action chain is produced and executed (FR-3.1).
- E-2.4 The Before/After screen shows a non-zero change in at least three state fields.
- E-2.5 Antigravity Walkthrough documents exist for each of the five agents in `/antigravity-artifacts/walkthroughs/`.

---

### Phase 3 — Scenario Coverage and Robustness (Day 4)

**Objective:** Add Scenarios S2 (contradiction-heavy) and S3 (failure and recovery), produce the baseline comparison, and harden the demo.

**Entry criteria**
- Phase 2 exit criteria all green.
- S1 runs deterministically across three consecutive executions.

**Tasks**
- 4.A.1 Author S2 fixture: three sources with conflicting stock values; low-credibility news source attempting to spoof a crisis.
- 4.A.2 Author S3 fixture: configure mock supplier API to fail the first attempt of `order` and succeed on retry; configure a downstream action to require rollback.
- 4.A.3 Run S2 and S3 end-to-end; iterate on Insight prompts until contradiction resolution is correct (FR-2.4 to FR-2.6).
- 4.A.4 Implement and run the baseline comparison script (FR-7.1 to FR-7.3); commit the comparison table to `/docs/baseline.md`.
- 4.A.5 Cache LLM responses for all three scenarios to a local fixture file; verify offline-mode demo works (NFR-2.3).
- 4.A.6 Measure cost and latency per scenario; commit to `/docs/cost-latency.md` (NFR-5.1).
- 4.B.1 UI polish: animations on Before/After, contrast tuning on risk metrics, action-DAG layout.
- 4.B.2 Produce signed Android APK; verify installation on a physical device.
- 4.B.3 Implement offline-mode toggle on Scenarios screen.

**Exit criteria**
- E-3.1 All three scenarios pass acceptance tests (§10).
- E-3.2 Baseline comparison table is committed and shows the agentic system outperforming the baseline on at least four of six metrics.
- E-3.3 Offline mode plays S1, S2, S3 without any network call.
- E-3.4 APK installs and runs on a clean Android device.
- E-3.5 Cost-latency document committed.

---

### Phase 4 — Submission Packaging (Day 5)

**Objective:** Produce all required submission artefacts and submit.

**Entry criteria**
- Phase 3 exit criteria all green.
- Git repository tagged `phase-3-complete`.

**Tasks**
- 5.A.1 Write README covering: architecture, data schemas, tools/APIs, Antigravity role, setup steps, assumptions, privacy note, cost/latency, scalability discussion, baseline comparison, and limitations.
- 5.A.2 Export Antigravity artefacts to `/antigravity-artifacts/` (plans, walkthroughs, screen recordings, manager snapshots).
- 5.A.3 Draw architecture diagram as PNG; commit to `/docs/architecture.png`.
- 5.B.1 Record the workflow demo video (3–5 minutes) covering input → insight → action chain → simulation → before/after.
- 5.B.2 Record the Antigravity walkthrough video (2–3 minutes) showing the Manager surface and Plan documents in use.
- 5.B.3 Final end-to-end dry run of the demo on a clean machine.
- 5.B.4 Submit.

**Exit criteria**
- E-4.1 All items in §11 (Deliverables) are checked off.
- E-4.2 Submission upload is confirmed.
- E-4.3 Repository tagged `submitted`.

---

### Phase Slip-Recovery Rules
If a phase exit criterion is unmet at end of day:

- **Phase 1 slip:** Push Day 2 by 4 hours. Compress Day 2 into the afternoon. Drop Live Run real-time animation; render events on completion instead.
- **Phase 2 slip (end of Day 2):** Drop sub-step 2.B.2 (DAG rendering) to Day 3. Catch up.
- **Phase 2 slip (end of Day 3):** Defer S3 to Day 4 but reduce its scope: keep only the retry path, drop the rollback case. This still satisfies FR-4.3 and the "robustness evidence" mandate.
- **Phase 3 slip:** Replace live baseline run with a hand-written comparison table sourced from a Day-3 manual run. Skip APK signing; demo on emulator instead.
- **Phase 4 slip:** Submit with what is ready. Tag the repository as `submitted-partial` and document gaps in README.

---

## 10. Acceptance Test Cases

Each test case shall pass deterministically before the corresponding phase exit.

### AT-S1 — Happy Path (gate for Phase 2 exit)
- **Given** Scenario S1 fixtures loaded.
- **When** the operator runs S1.
- **Then** at least one source is rejected as stale (FR-1.3).
- **And** at least one contradiction is resolved with reason logged (FR-2.4).
- **And** a 3–5 action chain is generated and executed (FR-3.1).
- **And** the Before/After screen shows stockout risk decreasing by ≥ 30 percentage points.
- **And** total runtime is ≤ 20 seconds (NFR-1.1).

### AT-S2 — Contradiction-Heavy (gate for Phase 3 exit)
- **Given** Scenario S2 fixtures with three conflicting stock values, one from a low-credibility news source.
- **When** the operator runs S2.
- **Then** the Insight Agent emits a `ConflictReport` referencing all three signals (FR-2.4).
- **And** the low-credibility source is not selected as the winning signal.
- **And** if the resolved confidence is below 0.6, the plan contains an `investigate` action (FR-2.6, FR-3.2).

### AT-S3 — Failure and Recovery (gate for Phase 3 exit)
- **Given** Scenario S3 fixtures with the mock supplier API configured to fail the first attempt.
- **When** the operator runs S3.
- **Then** the first `order` action returns status `failed`.
- **And** the Executor retries and the retry returns status `success` (FR-4.3).
- **And** at least one prior state mutation is rolled back if a dependent action becomes invalid (FR-4.5).
- **And** the trace contains a `rolled_back` event visible on the Live Run screen.

### AT-NFR — Cross-Cutting
- **AT-NFR-1** Three consecutive runs of S1 produce equivalent final risk metrics (within ±5 percentage points) (NFR-2.1).
- **AT-NFR-2** Each scenario run reports token cost ≤ USD 0.20 (NFR-5.1).
- **AT-NFR-3** With network disabled, S1, S2, S3 still run to completion using cached responses (NFR-2.3).
- **AT-NFR-4** Mobile cold start to Scenarios screen ≤ 2 seconds (NFR-1.3).

---

## 11. Deliverables

Deliverables required for submission. All items must be present at Phase 4 exit.

- [ ] D-1 Flutter APK (Android), signed and installable.
- [ ] D-2 Public GitHub repository containing:
  - [ ] D-2.1 `/mobile/` Flutter source.
  - [ ] D-2.2 `/backend/` FastAPI source and agent crew.
  - [ ] D-2.3 `/scenarios/S1/`, `/scenarios/S2/`, `/scenarios/S3/` fixture files.
  - [ ] D-2.4 `/antigravity-artifacts/plans/` — one Plan document per major task.
  - [ ] D-2.5 `/antigravity-artifacts/walkthroughs/` — one Walkthrough per agent.
  - [ ] D-2.6 `/antigravity-artifacts/screen-recordings/` — Antigravity Manager screen recordings.
  - [ ] D-2.7 `/docs/architecture.png` — architecture diagram.
  - [ ] D-2.8 `/docs/baseline.md` — baseline comparison table.
  - [ ] D-2.9 `/docs/cost-latency.md` — cost and latency measurements.
  - [ ] D-2.10 `/README.md` — covering all topics in §11.A.
- [ ] D-3 Workflow demo video (3–5 minutes).
- [ ] D-4 Antigravity walkthrough video (2–3 minutes).
- [ ] D-5 Antigravity trace exports for S1, S2, S3.

### 11.A README Required Sections
1. Project summary.
2. Architecture overview (with diagram).
3. Data schemas and source types.
4. Tools and APIs used (Gemini, ADK, Flutter, FastAPI, Antigravity).
5. Antigravity role in development.
6. Setup steps for local reproduction.
7. Assumptions and dependencies.
8. Privacy note (synthetic data, no PII).
9. Cost and latency measurements.
10. Scalability discussion (10× and 100× scenarios).
11. Baseline comparison.
12. Limitations and known issues.

---

## 12. Glossary

| Term | Definition |
|---|---|
| Action chain | A 3–5 step DAG of typed actions the system commits to executing in the sandbox. |
| Agent | A specialised reasoning component in the runtime crew (Ingestion, Insight, Planner, Executor, Supervisor). |
| Antigravity | Google's agent-first IDE used as the development environment, distinct from the runtime agent framework. |
| Baseline | The naive reactive heuristic implementation used for benchmark comparison. |
| Implication | The business-impact interpretation of a signal, quantified in PKR, customers, or time. |
| Increment | A self-contained development unit producing a demonstrable state. |
| Resolved signal | A signal that has passed contradiction resolution and carries a confidence score and resolution reason. |
| Sandbox | The mutable mock business state against which simulated actions execute. |
| Signal | A typed, quantified observation extracted from a source document. |
| Trace event | A persisted record of one agent invocation including input, output, latency, and cost. |
| Walking skeleton | The Phase 1 deliverable: an end-to-end pipeline with stubbed internals. |
