"""Pydantic models — single source of truth for all data shapes (SRS §6.2 & §6.3)."""

from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from typing import Any, Literal
from pydantic import BaseModel, Field
import uuid


# ── Helpers ──────────────────────────────────────────────────────────────────

def _uuid() -> str:
    return str(uuid.uuid4())


# ── Enumerations ─────────────────────────────────────────────────────────────

class SourceKind(str, Enum):
    PDF = "pdf"
    CSV = "csv"
    JSON = "json"
    EMAIL = "email"
    NEWS_HTML = "news_html"
    NEWS_MHTML = "news_mhtml"


class SignalKind(str, Enum):
    SALES_CHANGE = "sales_change"
    STOCK_LEVEL = "stock_level"
    SUPPLIER_STATUS = "supplier_status"
    PRICE_CHANGE = "price_change"
    COMPLAINT_CLUSTER = "complaint_cluster"
    EXTERNAL_SHOCK = "external_shock"


class ActionKind(str, Enum):
    VALIDATE = "validate"
    NOTIFY = "notify"
    ORDER = "order"
    ADJUST_ETA = "adjust_eta"
    SCHEDULE_MONITOR = "schedule_monitor"
    INVESTIGATE = "investigate"
    ROLLBACK = "rollback"


class ExecutionStatus(str, Enum):
    SUCCESS = "success"
    FAILED = "failed"
    RETRIED = "retried"
    ROLLED_BACK = "rolled_back"


class Urgency(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class RunPhase(str, Enum):
    PENDING = "pending"
    INGESTION = "ingestion"
    INSIGHT = "insight"
    PLANNING = "planning"
    EXECUTION = "execution"
    COMPLETED = "completed"
    FAILED = "failed"


# ── Source Ingestion ─────────────────────────────────────────────────────────

class SourceDocument(BaseModel):
    """A normalised input source (FR-1.2)."""
    id: str = Field(default_factory=_uuid)
    kind: SourceKind
    fetched_at: datetime
    content: str | dict | list
    credibility_prior: float = Field(ge=0, le=1)
    recency_days: float
    filename: str = ""
    content_hash: str = ""


# ── Signals ──────────────────────────────────────────────────────────────────

class Signal(BaseModel):
    """A typed, quantified observation extracted from a source (FR-2.1)."""
    id: str = Field(default_factory=_uuid)
    kind: SignalKind
    sku: str | None = None
    metric: str
    value: float
    delta_vs_baseline_pct: float | None = None
    source_doc_ids: list[str]
    extracted_at: datetime = Field(default_factory=datetime.utcnow)


class ConflictReport(BaseModel):
    """Contradiction report when signals disagree (FR-2.4)."""
    id: str = Field(default_factory=_uuid)
    metric: str
    sku: str | None = None
    conflicting_signal_ids: list[str]
    winning_signal_id: str
    resolution_reason: str
    confidence: float = Field(ge=0, le=1)


class ResolvedSignal(Signal):
    """A signal post contradiction-resolution (FR-2.5)."""
    confidence: float = Field(ge=0, le=1)
    conflicting_signal_ids: list[str] = Field(default_factory=list)
    resolution_reason: str = ""
    low_confidence: bool = False  # flagged when < 0.6 (FR-2.6)


# ── Actions ──────────────────────────────────────────────────────────────────

class Action(BaseModel):
    """A single step in the action chain (FR-3.1 – FR-3.7)."""
    id: str = Field(default_factory=_uuid)
    kind: ActionKind
    params: dict = Field(default_factory=dict)
    depends_on: list[str] = Field(default_factory=list)
    constraints_required: list[str] = Field(default_factory=list)
    rationale: str = ""
    estimated_impact_pkr: float = 0
    customers_affected: int = 0
    urgency: Urgency = Urgency.MEDIUM


class ActionPlan(BaseModel):
    """The full action plan — a DAG of 3-5 actions (FR-3.1)."""
    id: str = Field(default_factory=_uuid)
    actions: list[Action]
    total_estimated_impact_pkr: float = 0
    constraint_violations: list[str] = Field(default_factory=list)
    is_executable: bool = True


# ── Execution ────────────────────────────────────────────────────────────────

class ExecutionResult(BaseModel):
    """Result of simulating one action (FR-4.1)."""
    action_id: str
    status: ExecutionStatus
    state_diff: dict = Field(default_factory=dict)
    latency_ms: int = 0
    tokens_used: int = 0
    error: str | None = None


# ── Business State / Sandbox ─────────────────────────────────────────────────

class RiskMetrics(BaseModel):
    stockout_risk_pct: float = 0.0
    revenue_at_risk_pkr: float = 0.0
    days_of_stock_remaining: int = 0
    pending_customer_orders_affected: int = 0


class BusinessState(BaseModel):
    """Sandbox state (SRS §6.3)."""
    inventory: dict[str, int] = Field(default_factory=dict)       # sku → units
    customer_etas: dict[str, str] = Field(default_factory=dict)   # order_id → ISO date
    supplier_status: dict[str, str] = Field(default_factory=dict) # supplier → status
    notification_queue: list[dict] = Field(default_factory=list)
    open_orders: list[dict] = Field(default_factory=list)
    risk_metrics: RiskMetrics = Field(default_factory=RiskMetrics)
    validated_skus: list[str] = Field(default_factory=list)
    investigations: list[dict] = Field(default_factory=list)
    scheduled_checks: list[dict] = Field(default_factory=list)


class StateDiff(BaseModel):
    """Before vs after comparison (FR-6.3)."""
    before: BusinessState
    after: BusinessState
    changes_summary: dict = Field(default_factory=dict)


# ── Trace ────────────────────────────────────────────────────────────────────

class TraceEvent(BaseModel):
    """One entry in the agent trace log (FR-5.1)."""
    id: str = Field(default_factory=_uuid)
    run_id: str
    agent_name: str
    event_type: str  # e.g. "agent_start", "agent_end", "filtered_out", "conflict_resolved"
    input_summary: str = ""
    output_summary: str = ""
    detail: dict | list | str | None = None
    latency_ms: int = 0
    tokens_used: int = 0
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ── Run ──────────────────────────────────────────────────────────────────────

class RunSummary(BaseModel):
    """High-level run metadata."""
    run_id: str = Field(default_factory=_uuid)
    scenario_id: str
    phase: RunPhase = RunPhase.PENDING
    started_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: datetime | None = None
    total_latency_ms: int = 0
    total_tokens_used: int = 0
    total_cost_usd: float = 0.0
    error: str | None = None
    trigger_type: str = "manual"
    trigger_reason: str | None = None


# ── API Request / Response ───────────────────────────────────────────────────

class RunStartRequest(BaseModel):
    offline_mode: bool = False
    trigger_type: str = "manual"
    trigger_reason: str | None = None


class RunStartResponse(BaseModel):
    run_id: str
    scenario_id: str
    status: str = "started"


class RunDetailResponse(BaseModel):
    summary: RunSummary
    trace_events: list[TraceEvent] = Field(default_factory=list)
    state_diff: StateDiff | None = None
    action_plan: ActionPlan | None = None


class ScenarioInfo(BaseModel):
    """Scenario metadata for the Scenarios screen."""
    id: str
    title: str
    description: str
    source_count: int
    tags: list[str] = Field(default_factory=list)
