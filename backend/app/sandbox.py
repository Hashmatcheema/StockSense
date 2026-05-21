"""Business-state sandbox — mutable mock of Khan Traders' state (SRS §6.3)."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from app.schemas import BusinessState, RiskMetrics, StateDiff
from app import database as db


class Sandbox:
    """In-process sandbox that loads from a scenario's initial_state.json,
    supports mutation via state diffs, and provides snapshot / rollback."""

    def __init__(self, initial_state: BusinessState) -> None:
        self._initial = initial_state.model_copy(deep=True)
        self._current = initial_state.model_copy(deep=True)
        self._snapshots: list[BusinessState] = []

    # ── Accessors ────────────────────────────────────────────────────────────

    @property
    def state(self) -> BusinessState:
        return self._current

    @property
    def initial_state(self) -> BusinessState:
        return self._initial

    # ── Snapshot / Rollback (FR-4.6) ─────────────────────────────────────────

    def take_snapshot(self) -> int:
        """Save a copy of the current state. Returns snapshot index."""
        self._snapshots.append(self._current.model_copy(deep=True))
        return len(self._snapshots) - 1

    def rollback(self, snapshot_idx: int | None = None) -> None:
        """Roll back to a snapshot. None → roll back to initial state."""
        if snapshot_idx is None:
            self._current = self._initial.model_copy(deep=True)
        elif 0 <= snapshot_idx < len(self._snapshots):
            self._current = self._snapshots[snapshot_idx].model_copy(deep=True)

    # ── Mutations ────────────────────────────────────────────────────────────

    def apply_diff(self, diff: dict) -> None:
        """Apply a state-mutation dict to the current state.

        diff format examples:
          {"inventory": {"SKU-001": -50}}           → subtract 50 units
          {"supplier_status": {"Karachi Cool": "delayed"}}
          {"risk_metrics": {"stockout_risk_pct": -30.0}}
          {"notification_queue": [{"to": "...", "msg": "..."}]}
          {"open_orders": [{"sku": "...", "qty": 100}]}
          {"validated_skus": ["SKU-001"]}
          {"investigations": [{"reason": "...", ...}]}
          {"scheduled_checks": [{"scenario_id": "...", ...}]}
        """
        s = self._current

        # Inventory deltas
        if "inventory" in diff:
            for sku, delta in diff["inventory"].items():
                current = s.inventory.get(sku, 0)
                s.inventory[sku] = max(0, current + delta)

        # Supplier status overwrite
        if "supplier_status" in diff:
            for supplier, status in diff["supplier_status"].items():
                s.supplier_status[supplier] = status

        # Customer ETAs overwrite
        if "customer_etas" in diff:
            for order_id, eta in diff["customer_etas"].items():
                s.customer_etas[order_id] = eta

        # Notification queue append
        if "notification_queue" in diff:
            for notif in diff["notification_queue"]:
                s.notification_queue.append(notif)

        # Open orders append
        if "open_orders" in diff:
            for order in diff["open_orders"]:
                s.open_orders.append(order)

        # Risk metrics delta
        if "risk_metrics" in diff:
            rm = diff["risk_metrics"]
            if "stockout_risk_pct" in rm:
                s.risk_metrics.stockout_risk_pct = max(
                    0, min(100, s.risk_metrics.stockout_risk_pct + rm["stockout_risk_pct"])
                )
            if "revenue_at_risk_pkr" in rm:
                s.risk_metrics.revenue_at_risk_pkr = max(
                    0, s.risk_metrics.revenue_at_risk_pkr + rm["revenue_at_risk_pkr"]
                )
            if "days_of_stock_remaining" in rm:
                s.risk_metrics.days_of_stock_remaining = max(
                    0, s.risk_metrics.days_of_stock_remaining + rm["days_of_stock_remaining"]
                )
            if "pending_customer_orders_affected" in rm:
                s.risk_metrics.pending_customer_orders_affected = max(
                    0, s.risk_metrics.pending_customer_orders_affected + rm["pending_customer_orders_affected"]
                )

        # Validated SKUs append
        if "validated_skus" in diff:
            for sku in diff["validated_skus"]:
                if sku and sku not in s.validated_skus:
                    s.validated_skus.append(sku)

        # Investigations append
        if "investigations" in diff:
            for inv in diff["investigations"]:
                s.investigations.append(inv)

        # Scheduled checks append
        if "scheduled_checks" in diff:
            for chk in diff["scheduled_checks"]:
                s.scheduled_checks.append(chk)

    def revert_diff(self, diff: dict) -> None:
        """Reverse a previously applied diff (for rollback of specific actions)."""
        inverted: dict = {}

        if "inventory" in diff:
            inverted["inventory"] = {sku: -delta for sku, delta in diff["inventory"].items()}
        if "risk_metrics" in diff:
            inverted["risk_metrics"] = {k: -v for k, v in diff["risk_metrics"].items()}
        # For appended items we can't cleanly invert, but best-effort pop
        if "notification_queue" in diff:
            for _ in diff["notification_queue"]:
                if self._current.notification_queue:
                    self._current.notification_queue.pop()
        if "open_orders" in diff:
            for _ in diff["open_orders"]:
                if self._current.open_orders:
                    self._current.open_orders.pop()

        if inverted:
            self.apply_diff(inverted)

    # ── Diff generation ──────────────────────────────────────────────────────

    def compute_diff(self) -> StateDiff:
        """Compute a StateDiff between initial and current state."""
        before = self._initial
        after = self._current
        changes: dict = {}

        # Inventory changes
        inv_changes = {}
        all_skus = set(before.inventory) | set(after.inventory)
        for sku in all_skus:
            b = before.inventory.get(sku, 0)
            a = after.inventory.get(sku, 0)
            if b != a:
                inv_changes[sku] = {"before": b, "after": a, "delta": a - b}
        if inv_changes:
            changes["inventory"] = inv_changes

        # Risk metrics
        if before.risk_metrics != after.risk_metrics:
            changes["risk_metrics"] = {
                "stockout_risk_pct": {
                    "before": before.risk_metrics.stockout_risk_pct,
                    "after": after.risk_metrics.stockout_risk_pct,
                },
                "revenue_at_risk_pkr": {
                    "before": before.risk_metrics.revenue_at_risk_pkr,
                    "after": after.risk_metrics.revenue_at_risk_pkr,
                },
            }

        # Supplier status
        sup_changes = {}
        for sup in set(before.supplier_status) | set(after.supplier_status):
            b = before.supplier_status.get(sup, "unknown")
            a = after.supplier_status.get(sup, "unknown")
            if b != a:
                sup_changes[sup] = {"before": b, "after": a}
        if sup_changes:
            changes["supplier_status"] = sup_changes

        # Customer ETAs
        eta_changes = {}
        for oid in set(before.customer_etas) | set(after.customer_etas):
            b_eta = before.customer_etas.get(oid)
            a_eta = after.customer_etas.get(oid)
            if b_eta != a_eta:
                eta_changes[oid] = {"before": b_eta, "after": a_eta}
        if eta_changes:
            # Compute average days shifted
            total_days = 0
            count = 0
            examples = []
            for oid, vals in eta_changes.items():
                b_str = vals["before"]
                a_str = vals["after"]
                if b_str and a_str:
                    try:
                        b_date = datetime.fromisoformat(b_str).date()
                        a_date = datetime.fromisoformat(a_str).date()
                        delta_days = (a_date - b_date).days
                        total_days += delta_days
                        count += 1
                        if len(examples) < 3:
                            examples.append({
                                "order_id": oid,
                                "before": b_str,
                                "after": a_str,
                                "days_shifted": delta_days,
                            })
                    except (ValueError, TypeError):
                        pass
            changes["customer_etas"] = {
                "orders_shifted": len(eta_changes),
                "avg_days_shifted": round(total_days / max(1, count)),
                "examples": examples,
            }

        # Notifications and orders count
        changes["notifications_added"] = len(after.notification_queue) - len(before.notification_queue)
        changes["orders_added"] = len(after.open_orders) - len(before.open_orders)

        # New state fields
        validated_added = len(after.validated_skus) - len(before.validated_skus)
        if validated_added > 0:
            changes["validated_skus_added"] = validated_added

        investigations_added = len(after.investigations) - len(before.investigations)
        if investigations_added > 0:
            changes["investigations_added"] = investigations_added

        scheduled_added = len(after.scheduled_checks) - len(before.scheduled_checks)
        if scheduled_added > 0:
            changes["scheduled_checks_added"] = scheduled_added

        return StateDiff(before=before, after=after, changes_summary=changes)

    # ── Persistence helpers ──────────────────────────────────────────────────

    async def persist_snapshot(self, run_id: str, label: str) -> None:
        await db.save_snapshot(run_id, label, self._current.model_dump_json())

    @classmethod
    def from_before_after(cls, before: BusinessState, after: BusinessState) -> "Sandbox":
        """Reconstruct a Sandbox from a persisted before/after pair for diff computation."""
        instance = cls(before)
        instance._current = after
        return instance

    @classmethod
    def from_json(cls, data: dict) -> "Sandbox":
        return cls(BusinessState(**data))

    @classmethod
    def from_file(cls, path: str | Path) -> "Sandbox":
        with open(path) as f:
            return cls(BusinessState(**json.load(f)))
