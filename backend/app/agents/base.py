"""Base agent class — shared interface for all crew agents."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from app.schemas import TraceEvent
from app.trace_logger import trace_logger


class BaseAgent(ABC):
    """Abstract base for all StockSense agents."""

    name: str = "base"

    def __init__(self, run_id: str) -> None:
        self.run_id = run_id
        self._total_tokens = 0
        self._total_latency_ms = 0

    @abstractmethod
    async def run(self, input_data: Any) -> Any:
        """Execute the agent's core logic."""
        ...

    # ── Trace helpers ────────────────────────────────────────────────────────

    async def emit_event(
        self,
        event_type: str,
        input_summary: str = "",
        output_summary: str = "",
        detail: Any = None,
        latency_ms: int = 0,
        tokens_used: int = 0,
    ) -> None:
        """Emit a trace event for this agent step."""
        event = TraceEvent(
            run_id=self.run_id,
            agent_name=self.name,
            event_type=event_type,
            input_summary=input_summary,
            output_summary=output_summary,
            detail=detail,
            latency_ms=latency_ms,
            tokens_used=tokens_used,
        )
        self._total_tokens += tokens_used
        self._total_latency_ms += latency_ms
        await trace_logger.emit(event)

    @property
    def stats(self) -> dict:
        return {
            "agent": self.name,
            "total_tokens": self._total_tokens,
            "total_latency_ms": self._total_latency_ms,
        }
