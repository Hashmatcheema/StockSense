import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // Compile-time override via --dart-define=STOCKSENSE_API=http://...
  static const _envBase = String.fromEnvironment(
    'STOCKSENSE_API',
    defaultValue: 'http://127.0.0.1:8000',
  );

  // Runtime override (persisted via shared_preferences)
  static String? _runtimeOverride;

  static String get baseUrl => _runtimeOverride ?? _envBase;

  /// Load persisted API base URL from shared_preferences.
  /// Call this in main() before runApp().
  static Future<void> loadPersistedBase() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('api_base');
    if (saved != null && saved.isNotEmpty) {
      _runtimeOverride = saved;
    }
  }

  /// Set and persist a new API base URL.
  static Future<void> setBaseUrl(String url) async {
    _runtimeOverride = url.trimRight();
    // Remove trailing slash if present
    if (_runtimeOverride!.endsWith('/')) {
      _runtimeOverride = _runtimeOverride!.substring(0, _runtimeOverride!.length - 1);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base', _runtimeOverride!);
  }

  /// Clear the runtime override (revert to env/default).
  static Future<void> clearBaseUrl() async {
    _runtimeOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_base');
  }

  static String scenariosRun(String scenarioId) =>
      '$baseUrl/scenarios/$scenarioId/run';
  static String runEvents(String runId) => '$baseUrl/runs/$runId/events';
  static String runStateDiff(String runId) => '$baseUrl/runs/$runId/state-diff';
  static String runExport(String runId) => '$baseUrl/runs/$runId/export';
  static String runDetail(String runId) => '$baseUrl/runs/$runId';
  static String latestRuns([int limit = 5]) => '$baseUrl/runs/latest?limit=$limit';
  static String monitorConfig() => '$baseUrl/monitor/config';
}
