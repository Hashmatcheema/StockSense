# StockSense Phase 1+2 Reshaped Audit — Implementation Plan

Fix all 13 robustness items (Part 1) and rebuild the UI to a light semantic theme (Part 2). No S2/S3 fixture creation, no S3 retry rebuild, no baseline benchmark, no model split.

## User Review Required

> [!IMPORTANT]
> **Package additions**: `google_fonts`, `shared_preferences`, `share_plus`, `path_provider` will be added to `pubspec.yaml`. These are all stable, well-maintained Flutter packages.

> [!WARNING]
> **Breaking theme change**: The entire app switches from dark blue/purple to a light off-white theme with semantic colors. All existing color constants across 4 screen files will be deleted and replaced with imports from a new `lib/theme/app_theme.dart`.

> [!IMPORTANT]
> **SSE replay mechanism**: The backend `event_stream()` will now replay persisted events before subscribing to live ones. The client deduplicates by event ID. This changes the SSE contract — old clients receiving duplicate events would need the dedup logic.

## Open Questions

> [!IMPORTANT]
> **`google_fonts` requires network on first use** — Inter and JetBrains Mono will be fetched from Google Fonts API on first launch. On a phone with no internet this falls back to system fonts. Is this acceptable, or should we bundle the `.ttf` files? (Bundling is listed as Phase 4 scope.)

---

## Proposed Changes

### Part 1: Robustness Fixes

---

#### 1. SSE Stream Race Condition Fix

##### [MODIFY] [trace_logger.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/trace_logger.py)
- Add a `dict[str, asyncio.Lock]` for per-run locks
- In `event_stream()`: acquire lock → query `db.get_trace_events(run_id)` → yield each as SSE → subscribe queue → release lock
- Each persisted event yielded as `data: {json}\n\n` (same format as live)

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- Add `final Set<String> _seenIds = {};`
- In SSE listener: `if (!_seenIds.add(event.id)) return;` before appending

---

#### 2. Mobile API Host Configuration

##### [MODIFY] [api_config.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/config/api_config.dart)
- Replace hard-coded `localhost:8000` with compile-time env + runtime override via `shared_preferences`
- Add `loadPersistedBase()` and `setBaseUrl()` static methods

##### [MODIFY] [main.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/main.dart)
- Call `WidgetsFlutterBinding.ensureInitialized()` + `ApiConfig.loadPersistedBase()` before `runApp()`

##### [MODIFY] [settings_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/settings_screen.dart)
- Add "API URL" text field + Save button bound to `ApiConfig.setBaseUrl()`
- Helper text: "Use http://10.0.2.2:8000 on emulator, http://<LAN-IP>:8000 on device"

##### [MODIFY] [pubspec.yaml](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/pubspec.yaml)
- Add `shared_preferences: ^2.5.0`

---

#### 3. Real Actions (Not Mocks) on Before/After

##### [MODIFY] [runs.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/routes/runs.py)
- In `get_state_diff`: parse `action_plan` JSON server-side, return `action_plan` as structured dict (not string) alongside `actions_taken`

##### [MODIFY] [state_diff.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/models/state_diff.dart)
- Add `TakenAction` class with `kind` and `rationale` fields
- Add `List<TakenAction> actionsTaken` to `StateDiff`, parsed from `actions_taken` in JSON

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- Delete `mockActions` and the comment admitting it's a mock
- Render `_diff.actionsTaken` as numbered rows; show "No actions executed" when empty

---

#### 4. Every Action Kind Mutates the Sandbox

##### [MODIFY] [schemas.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/schemas.py)
- Add to `BusinessState`:
  - `validated_skus: list[str] = Field(default_factory=list)`
  - `investigations: list[dict] = Field(default_factory=list)`
  - `scheduled_checks: list[dict] = Field(default_factory=list)`

##### [MODIFY] [sandbox.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/sandbox.py)
- Extend `apply_diff()` to handle `validated_skus`, `investigations`, `scheduled_checks` (append-only)
- Extend `compute_diff()` to surface counts: `validated_skus_added`, `investigations_added`, `scheduled_checks_added`
- Add `customer_etas` diff comparison (item 6 combined here)

##### [MODIFY] [executor.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/agents/executor.py)
- `_exec_validate`: call `self.sandbox.apply_diff(diff)` after building diff
- `_exec_investigate`: restructure diff key to `investigations` list, call `apply_diff`
- `_exec_schedule_monitor`: call `self.sandbox.apply_diff(diff)`
- `_exec_adjust_eta`: call `self.sandbox.apply_diff(diff)` (currently directly mutates state, switch to proper `apply_diff`)

---

#### 5. Realistic Risk Delta on Order

##### [MODIFY] [executor.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/agents/executor.py)
- In `_exec_order`: replace hard-coded `-35` / `-1500000` with quantity-based calculation
- Add `self._orders_executed` counter for diminishing returns
- Cap risk delta at -60pp

---

#### 6. Customer ETAs in Diff

##### [MODIFY] [sandbox.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/sandbox.py)
- In `compute_diff()`: compare `before.customer_etas` vs `after.customer_etas`, compute days shifted, add to `changes_summary["customer_etas"]`

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- Add "Customer ETAs" section below Actions Taken, rendering `orders_shifted`, `avg_days_shifted`, and example list

---

#### 7. Deterministic Recency

##### [MODIFY] [ingestion.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/agents/ingestion.py)
- Check `entry.get("recency_days")` first; fall back to mtime calculation

##### [MODIFY] [config.yaml](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/scenarios/S1/config.yaml)
- Add `recency_days: 18` to `news_fuel_prices.html` (triggers stale rejection)
- Add `recency_days: 2` to all other sources

---

#### 8. Insight Grouping Fix

##### [MODIFY] [insight.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/agents/insight.py)
- Change grouping key from `(s.metric, s.sku)` to `(s.kind, s.metric, s.sku)`
- For groups where every `sku is None`: only treat as conflict if values differ by >10% AND metric matches exactly
- Otherwise emit each as its own `ResolvedSignal` with `resolution_reason="single source, no conflict"`

---

#### 9. Export Trace Works

##### [MODIFY] [api_service.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/services/api_service.dart)
- Add `downloadTraceJson(String runId)` that GETs `/runs/{runId}/export`, returns body as string

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- Wire export button to write trace to temp file, share via `Share.shareXFiles`

##### [MODIFY] [pubspec.yaml](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/pubspec.yaml)
- Add `share_plus: ^10.1.0`, `path_provider: ^2.1.0`

---

#### 10. Cost Display Fix

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- Replace `_totalTokens * 0.000001` with `_totalTokens / 1000000 * 0.30`

---

#### 11. Action DAG Card (FR-6.2)

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- When `plan_generated` event arrives, fetch `/runs/{runId}` and parse `action_plan`
- Render a collapsible "Action Plan · N steps · Rs X impact" card above the trace list
- Each row: number, kind chip, rationale, dependency labels for non-roots

---

#### 12. Auto-Scroll Live Run

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- Add `ScrollController` to ListView
- After each `setState` that appends an event, schedule post-frame callback to `animateTo(maxScrollExtent, duration: 200ms)`

---

#### 13. Monitor Robustness

##### [MODIFY] [monitor.py](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/backend/app/monitor.py)
- Before calling `load_initial_state`, verify `config.yaml` exists AND every source file exists
- `continue` silently if missing (already partially done for config.yaml — extend to sources)

---

### Part 2: UI Rebuild

---

#### 14. Design Token File

##### [NEW] [app_theme.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/theme/app_theme.dart)
- `AppColors` class with canvas, text, semantic, action, tint color groups
- All colors as `static const Color` values
- Helper method `getSemanticColorForEventType(String eventType)` for trace rows
- Helper method `getAgentIcon(String agentName)` for agent icons

##### [MODIFY] [scenarios_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/scenarios_screen.dart)
- Delete lines 7-17 (`bgPrimary`, `bgSurface`, etc.)
- Import `AppColors` from `app_theme.dart`
- Replace all color references

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- Delete duplicated color constants
- Import and use `AppColors`

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- Delete duplicated color constants
- Import and use `AppColors`

##### [MODIFY] [settings_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/settings_screen.dart)
- Delete lines 5-14 (duplicated color constants)
- Import and use `AppColors`

---

#### 15. Light Theme + Google Fonts

##### [MODIFY] [main.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/main.dart)
- Switch to `Brightness.light`
- Use `AppColors.bg` as scaffold background
- Use `GoogleFonts.interTextTheme()` for text
- Add `google_fonts: ^6.2.1` to pubspec

---

#### 16. Semantic Color Rules

Applied across all screen files as part of items 14, 19, 20:
- Agent name always `AppColors.textPrimary`, Inter Medium
- Trace row left border: semantic based on `event_type` not `agent_name`
- Stockout risk: stateCritical ≥60, stateWarn 30–59, stateOk <30
- Supplier pill: stateOk/tintOk for active, stateWarn/tintWarn for delayed, stateCritical/tintCritical for silent

---

#### 17. Iconography

All icons added per the audit table. Implemented via helper methods in `app_theme.dart` and used in each screen.

---

#### 18. Before/After Redesign

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- Replace `DataTable` with 2-column grid of `MetricCard` widgets
- Each card: icon + label (uppercase 11sp) + "65% → 24%" (28sp semibold with semantic color) + delta chip
- Metrics: Stockout Risk, Revenue at Risk, Days of Stock, Affected Orders, Supplier Status, Notifications Sent
- Largest absolute change gets tinted background
- Below grid: Actions Taken, Customer ETAs, Agent Summary sections

---

#### 19. Live Run Screen Redesign

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- Stats bar: 3 pills (icon + label + mono value) for Latency, Tokens, Cost
- Status: single 8px pulsing dot (stateWarn running, stateOk done)
- Trace row: white card on bg, border, 4px semantic left strip, agent icon + name Inter Medium, event pill in surface2, right-aligned timestamp mm:ss.SSS JetBrainsMono
- Expanded JSON: surface2 bg, JetBrainsMono 11sp

---

#### 20. Scenarios Screen Cleanup

##### [MODIFY] [scenarios_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/scenarios_screen.dart)
- Extract `StatusPill` as real `StatelessWidget` with `label`, `color`, `tint` params
- Delete no-op `AnimatedOpacity` wrapping pulse dot; slow pulse to 1200ms
- Active Alerts: `tintCritical` bg, `stateCritical` left strip, `notifications_active_outlined` icon
- Each scenario row: leading icon (S1→local_shipping, S2→compare_arrows, S3→replay)
- Remove hard-coded "5 sources" — use `sourceCount` from Scenario model
- Header: "StockSense" left, "Khan Traders · Lahore" as subtitle (not separated by |)
- "RUN SCENARIO MANUALLY" → "Scenarios"
- Recent runs: 3-column layout, "Completed"/"Running" capitalized

---

#### 21. Empty/Error States

##### [MODIFY] [live_run_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/live_run_screen.dart)
- No events after 20s: `cloud_off_outlined` icon, "Backend not reachable", "Open Settings" button

##### [MODIFY] [before_after_screen.dart](file:///c:/Users/Admin/Desktop/StockSense/stock_sense/lib/screens/before_after_screen.dart)
- On 400 (run not complete): "Run still in progress", "Back" button

---

## Verification Plan

### Automated Tests
1. `flutter analyze` — no new warnings
2. Backend startup: `cd backend && python -m uvicorn main:app --host 0.0.0.0 --port 8000`
3. Run S1 scenario via API, verify SSE stream includes `agent_start` as first event
4. Verify `news_fuel_prices.html` appears as `filtered_out` with reason "stale"
5. Verify Before/After shows real action kinds (not mock)
6. Verify cost display is < $0.001 for typical run

### Manual Verification  
- Visual inspection of light theme across all screens
- Confirm semantic colors on trace rows, metric cards, supplier pills
- Verify Action Plan card appears on Live Run
- Test export trace button triggers share sheet
- Test API URL setting in Settings screen
