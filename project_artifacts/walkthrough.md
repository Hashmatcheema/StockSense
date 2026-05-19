# StockSense Phase 1+2 Reshaped Audit — Walkthrough

I have successfully completed the comprehensive audit for the StockSense platform. The implementation was divided into three main batches: backend robustness fixes, mobile platform configurations, and a full UI rebuild based on the new light-mode design system.

## 1. Backend Robustness Fixes

All 9 critical backend bugs causing demo failures have been resolved:

- **SSE Race Condition Fixed**: `trace_logger.py` now leverages a per-run `asyncio.Lock`. When a client connects, the stream first replays all previously persisted events from the database before subscribing to the live `asyncio.Queue`. 
- **Sandbox Mutations**: `BusinessState` now tracks `validated_skus`, `investigations`, and `scheduled_checks`. The `Sandbox.apply_diff()` method was completely rewritten to handle appending items to these new lists, allowing the `ExecutorAgent`'s actions to persist correctly across the simulation.
- **Realistic Risk Deltas**: `ExecutorAgent._exec_order` was updated to drop the hard-coded `-35` risk delta. It now computes coverage (`qty / daily_demand`) and applies diminishing returns if multiple orders are executed.
- **Deterministic Recency Checks**: To fix the flaky test `AT-S1`, `ingestion.py` now respects a `recency_days` key in the scenario's `config.yaml`. We updated `S1/config.yaml` to set `news_fuel_prices.html` to 18 days, ensuring it is deterministically rejected for being stale.
- **Insight Contradiction Grouping**: The `InsightAgent` grouping logic was updated. It now keys on `(kind, metric, sku)`. For generic metrics where `sku` is None (e.g., fuel prices), it requires an exact metric string match and >10% value divergence to classify as a conflict, eliminating false positives.
- **Structured Action Plans**: The `/runs/{run_id}/state-diff` endpoint now parses the `action_plan` JSON server-side and returns it as a structured dictionary, along with the backwards-compatible `actions_taken` array.
- **Customer ETA Comparison**: `Sandbox.compute_diff` now checks `before.customer_etas` vs `after.customer_etas`, calculates the days shifted, and returns a rich summary object including `orders_shifted`, `avg_days_shifted`, and up to 3 examples.
- **Monitor Robustness**: The daemon monitor now verifies that all source files listed in a scenario's `config.yaml` actually exist on disk before attempting to load them, preventing crashes on missing fixtures.

## 2. Flutter Services & Config

- **Mobile API Host**: Replaced the hard-coded `localhost:8000` with a robust configuration system in `api_config.dart`. It uses a compile-time environment variable (defaulting to `http://10.0.2.2:8000` for Android emulators) and allows for a persistent runtime override.
- **Export Trace**: Added `downloadTraceJson` to `ApiService`.
- **Dependencies**: Added `google_fonts`, `shared_preferences`, `share_plus`, and `path_provider` to `pubspec.yaml` and ran `flutter pub get`.

## 3. Full UI Rebuild

The entire app was rebuilt from the dark "AI demo" aesthetic to a professional light-mode supply-chain console.

> [!TIP]
> **Open the app in your emulator to see the new UI.** The entire application now uses `GoogleFonts.inter` for body text and `GoogleFonts.jetBrainsMono` for numerical data.

- **Design Tokens**: Created `AppColors` in `app_theme.dart` representing a rigorous semantic color system (e.g., `stateOk`=green, `stateWarn`=amber, `stateCritical`=red).
- **Scenarios Screen**: Features a cleaner layout, a status pill system, and explicit source counts and tags for each scenario.
- **Live Run Screen**: 
  - **Action DAG**: When the planner finishes, a collapsable "Action Plan" card appears above the trace list, detailing steps, kinds, rationales, and dependencies.
  - **Event Dedup & Scrolling**: Added client-side deduplication (to handle the new SSE replay mechanism) and auto-scrolling via `ScrollController`.
  - **Semantic Traces**: Trace events use a white card on an off-white background with a thick left border colored according to the semantic meaning of the event type.
- **Before/After Screen**: 
  - **Metric Grid**: Replaced the old data table with a 2x3 grid of metric cards. The metric with the largest absolute change is automatically highlighted with a tinted background.
  - **Real Actions**: Displays the actual `TakenAction` list parsed from the backend instead of hard-coded mocks.
  - **Customer ETAs**: Shows the number of delayed orders, average days shifted, and specific order examples.
  - **Export Trace**: The "Export Trace" button successfully downloads the full trace JSON and opens the native system share sheet.
- **Settings Screen**: Added a new section for updating and persisting the API Base URL.

### Next Steps
The Phase 1+2 Audit is complete. The system is now robust and features a professional UI. You can proceed to Phase 3 when ready.
