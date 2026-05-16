"""Business-state sandbox — mutable mock of Khan Traders' state (SRS §6.3)."""

from __future__ import annotations

import copy
import json
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

        # Notifications and orders count
        changes["notifications_added"] = len(after.notification_queue) - len(before.notification_queue)
        changes["orders_added"] = len(after.open_orders) - len(before.open_orders)

        return StateDiff(before=before, after=after, changes_summary=changes)

    # ── Persistence helpers ──────────────────────────────────────────────────

    async def persist_snapshot(self, run_id: str, label: str) -> None:
        await db.save_snapshot(run_id, label, self._current.model_dump_json())

    @classmethod
    def from_json(cls, data: dict) -> "Sandbox":
        return cls(BusinessState(**data))

    @classmethod
    def from_file(cls, path: str | Path) -> "Sandbox":
        with open(path) as f:
            return cls(BusinessState(**json.load(f)))
