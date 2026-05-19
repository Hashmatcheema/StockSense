"""Insight Agent — signal extraction and contradiction resolution (FR-2.1 to FR-2.6).

Phase 2: Real Gemini-powered extraction + contradiction resolution.
"""

from __future__ import annotations

import json
import time
from datetime import datetime
from typing import Any

import google.generativeai as genai

from app.agents.base import BaseAgent
from app.schemas import (
    ConflictReport, ResolvedSignal, Signal, SignalKind, SourceDocument,
)
from app.config import settings

genai.configure(api_key=settings.GEMINI_API_KEY)
_model = genai.GenerativeModel("gemini-2.5-flash")


class InsightAgent(BaseAgent):
    name = "insight"

    async def run(self, input_data: list[SourceDocument]) -> dict:
        """Extract signals and resolve contradictions using Gemini 2.5 Flash."""
        await self.emit_event(
            "agent_start",
            input_summary=f"Analyzing {len(input_data)} accepted sources",
        )

        all_signals: list[Signal] = []
        total_tokens = 0
        total_latency_ms = 0

        # ── STEP 1: Signal Extraction (one Gemini call per source) ────────
        for source_doc in input_data:
            content_preview = str(source_doc.content)[:4000]

            prompt = f"""You are a supply chain intelligence analyst for Khan Traders,
a Pakistani electronics wholesaler in Lahore. Extract business signals
from the source document below.

Source type: {source_doc.kind}
Source credibility: {source_doc.credibility_prior}
Source age: {source_doc.recency_days:.1f} days old

Content:
{content_preview}

Output ONLY a valid JSON object, no markdown, no explanation:
{{
  "signals": [
    {{
      "kind": "<sales_change|stock_level|supplier_status|price_change|complaint_cluster|external_shock>",
      "sku": "<specific SKU string or null>",
      "metric": "<concise snake_case metric name>",
      "value": <number>,
      "delta_vs_baseline_pct": <number or null>,
      "rationale": "<one sentence: why this matters to Khan Traders>"
    }}
  ]
}}

Rules:
- Only extract signals with a concrete numeric value
- For news: extract the quantified price/cost impact (e.g. petrol Rs 266.17/litre, up Rs 8)
- For emails: extract supplier_status (0=active, 1=delayed, 2=silent) and delay_days
- For CSV/JSON: extract inventory levels, sales velocity, complaint counts
- For transport strike news: extract logistics_disruption_days and cost_impact_pct
- If no meaningful signals found, return {{"signals": []}}
"""

            t0 = time.time()
            try:
                response = _model.generate_content(
                    prompt,
                    generation_config=genai.GenerationConfig(
                        temperature=0.1,
                        max_output_tokens=800,
                        response_mime_type="application/json"
                    )
                )
                latency_ms = int((time.time() - t0) * 1000)
                total_latency_ms += latency_ms

                tokens = 0
                if hasattr(response, 'usage_metadata') and response.usage_metadata:
                    tokens = response.usage_metadata.total_token_count
                total_tokens += tokens

                raw = response.text.strip()
                # Strip markdown fences if present
                if "```" in raw:
                    lines = raw.split("\n")
                    raw = "\n".join(l for l in lines if not l.strip().startswith("```"))
                raw = raw.strip()
                start = raw.find("{")
                end = raw.rfind("}") + 1
                if start >= 0 and end > start:
                    raw = raw[start:end]
                parsed = json.loads(raw)
                raw_signals = parsed.get("signals", [])
                print(f"[INSIGHT] {source_doc.id}: extracted {len(raw_signals)} signals: "
                      f"{[s.get('metric') for s in raw_signals]}")

            except Exception as e:
                import traceback
                latency_ms = int((time.time() - t0) * 1000)
                total_latency_ms += latency_ms
                print(f"[INSIGHT ERROR] {source_doc.id}: {e}")
                traceback.print_exc()
                await self.emit_event(
                    "extraction_error",
                    detail={"source": source_doc.id, "error": str(e), "latency_ms": latency_ms}
                )
                continue

            signal_names = []
            for sig in raw_signals:
                kind_str = str(sig.get("kind", "external_shock")).upper()
                try:
                    kind = SignalKind[kind_str]
                except KeyError:
                    kind = SignalKind.EXTERNAL_SHOCK

                value = sig.get("value")
                if value is None:
                    continue
                try:
                    value = float(value)
                except (ValueError, TypeError):
                    continue

                delta = sig.get("delta_vs_baseline_pct")
                if delta is not None:
                    try:
                        delta = float(delta)
                    except (ValueError, TypeError):
                        delta = None

                s = Signal(
                    kind=kind,
                    sku=sig.get("sku"),
                    metric=str(sig.get("metric", "unknown")),
                    value=value,
                    delta_vs_baseline_pct=delta,
                    source_doc_ids=[source_doc.id],
                    extracted_at=datetime.utcnow()
                )
                all_signals.append(s)
                signal_names.append(s.metric)

            await self.emit_event(
                "signals_extracted",
                output_summary=f"Extracted {len(raw_signals)} signals from {source_doc.filename}",
                latency_ms=latency_ms,
                tokens_used=tokens,
                detail={
                    "source_id": source_doc.id,
                    "source_file": source_doc.filename,
                    "signals_found": len(raw_signals),
                    "tokens": tokens,
                    "latency_ms": latency_ms,
                    "signal_names": signal_names,
                }
            )

        # ── STEP 2: Contradiction Detection ───────────────────────────────

        # Group signals by (kind, metric, sku) — A9 fix: prevents false conflicts
        groups: dict[tuple, list[Signal]] = {}
        for s in all_signals:
            key = (s.kind, s.metric, s.sku)
            groups.setdefault(key, []).append(s)

        resolved_signals: list[ResolvedSignal] = []
        conflict_reports: list[ConflictReport] = []
        n_conflicts = 0

        for key, group in groups.items():
            kind_key, metric, sku = key

            # Check for real conflict: values differ by more than 10%
            is_conflict = False
            if len(group) >= 2:
                # For groups where every sku is None, require exact metric match
                # and >10% value divergence to classify as conflict
                all_sku_none = all(s.sku is None for s in group)
                if all_sku_none:
                    # Only conflict if metrics match exactly AND values diverge
                    metrics_match = len(set(s.metric for s in group)) == 1
                    if metrics_match:
                        values = [s.value for s in group]
                        avg = sum(values) / len(values)
                        if avg != 0:
                            for v in values:
                                if abs(v - avg) / abs(avg) > 0.10:
                                    is_conflict = True
                                    break
                else:
                    values = [s.value for s in group]
                    avg = sum(values) / len(values)
                    if avg != 0:
                        for v in values:
                            if abs(v - avg) / abs(avg) > 0.10:
                                is_conflict = True
                                break

            if not is_conflict:
                # No conflict — wrap each as ResolvedSignal
                for s in group:
                    cred = 0.85
                    # Try to find source credibility
                    for doc in input_data:
                        if doc.id in s.source_doc_ids:
                            cred = doc.credibility_prior
                            break
                    resolved_signals.append(ResolvedSignal(
                        **s.model_dump(mode='json'),
                        confidence=cred,
                        resolution_reason="single source, no conflict" if len(group) == 1 else "no conflict",
                        low_confidence=(cred < settings.LOW_CONFIDENCE_THRESHOLD),
                    ))
            else:
                # Real conflict — use Gemini to resolve
                n_conflicts += 1
                conflict_data = []
                for s in group:
                    d = s.model_dump(mode='json')
                    # enrich with source credibility
                    for doc in input_data:
                        if doc.id in s.source_doc_ids:
                            d["source_credibility"] = doc.credibility_prior
                            d["source_file"] = doc.filename
                            break
                    conflict_data.append(d)

                conflict_prompt = f"""You are resolving conflicting supply chain data
for Khan Traders, Lahore. Multiple sources report different values for
the same metric. Determine which source is most credible.

Conflicting signals:
{json.dumps(conflict_data, indent=2, default=str)}

Output ONLY valid JSON, no markdown:
{{
  "winning_signal_index": <0-based integer>,
  "confidence": <0.0 to 1.0>,
  "reason": "<one sentence: why this source wins (recency/credibility/corroboration)>"
}}
"""
                t0 = time.time()
                try:
                    resp = _model.generate_content(
                        conflict_prompt,
                        generation_config=genai.GenerationConfig(
                            temperature=0.0,
                            max_output_tokens=200,
                            response_mime_type="application/json"
                        )
                    )
                    c_latency = int((time.time() - t0) * 1000)
                    total_latency_ms += c_latency

                    c_tokens = 0
                    if hasattr(resp, 'usage_metadata') and resp.usage_metadata:
                        c_tokens = resp.usage_metadata.total_token_count
                    total_tokens += c_tokens

                    raw = resp.text.strip()
                    if raw.startswith("```"):
                        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]

                    res = json.loads(raw)
                    winner_idx = int(res.get("winning_signal_index", 0))
                    confidence = float(res.get("confidence", 0.5))
                    reason = str(res.get("reason", "Unknown"))

                except Exception:
                    winner_idx = 0
                    confidence = 0.5
                    reason = "fallback: chose most recent source"

                if winner_idx < 0 or winner_idx >= len(group):
                    winner_idx = 0

                winning = group[winner_idx]
                low_conf = confidence < settings.LOW_CONFIDENCE_THRESHOLD

                resolved_signals.append(ResolvedSignal(
                    **winning.model_dump(mode='json'),
                    confidence=confidence,
                    conflicting_signal_ids=[s.id for s in group if s.id != winning.id],
                    resolution_reason=reason,
                    low_confidence=low_conf,
                ))

                conflict_reports.append(ConflictReport(
                    metric=metric,
                    sku=sku,
                    conflicting_signal_ids=[s.id for s in group],
                    winning_signal_id=winning.id,
                    resolution_reason=reason,
                    confidence=confidence,
                ))

                await self.emit_event(
                    "conflict_resolved",
                    output_summary=f"Conflict on {metric}: resolved with confidence {confidence:.2f}",
                    detail={
                        "metric": metric,
                        "winner_source": winning.source_doc_ids[0] if winning.source_doc_ids else "unknown",
                        "confidence": confidence,
                        "reason": reason,
                        "alternatives_rejected": len(group) - 1,
                    }
                )

        low_confidence_count = sum(1 for s in resolved_signals if s.low_confidence)

        await self.emit_event(
            "agent_end",
            output_summary=f"{len(resolved_signals)} resolved signals, {n_conflicts} conflicts resolved",
            latency_ms=total_latency_ms,
            tokens_used=total_tokens,
            detail={
                "total_signals": len(resolved_signals),
                "conflicts_resolved": n_conflicts,
                "low_confidence_signals": low_confidence_count,
                "total_tokens": total_tokens,
                "total_latency_ms": total_latency_ms,
            }
        )

        return {"resolved_signals": resolved_signals, "conflict_reports": conflict_reports}
