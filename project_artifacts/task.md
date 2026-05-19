# StockSense Phase 1+2 Audit — Task Tracker

## Backend Fixes
- [x] 1. schemas.py — Add validated_skus, investigations, scheduled_checks to BusinessState
- [x] 2. sandbox.py — Extend apply_diff + compute_diff (new fields + customer_etas)
- [x] 3. trace_logger.py — SSE replay race fix
- [x] 4. executor.py — Sandbox mutations + realistic risk delta
- [x] 5. ingestion.py — Deterministic recency
- [x] 6. insight.py — Grouping fix
- [x] 7. runs.py — Return action_plan as structured JSON
- [x] 8. monitor.py — Robustness check for missing fixtures
- [x] 9. S1/config.yaml — Add recency_days to sources

## Flutter Models, Services, Config
- [x] 10. pubspec.yaml — Add google_fonts, shared_preferences, share_plus, path_provider
- [x] 11. api_config.dart — Mobile API host with env + shared_preferences
- [x] 12. state_diff.dart — Add TakenAction model + actionsTaken
- [x] 13. api_service.dart — Add downloadTraceJson

## Flutter Theme + Screens
- [x] 14. NEW app_theme.dart — Design tokens
- [x] 15. main.dart — Light theme + Google Fonts + ApiConfig init
- [x] 16. scenarios_screen.dart — Full redesign
- [x] 17. live_run_screen.dart — Full redesign (SSE dedup, cost, DAG, auto-scroll, semantic, empty states)
- [x] 18. before_after_screen.dart — Full redesign (metric cards, real actions, customer ETAs, export)
- [x] 19. settings_screen.dart — API URL field + theme migration
