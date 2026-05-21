import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // Compile-time override via --dart-define=STOCKSENSE_API=http://...
  static const _envBase = String.fromEnvironment(
    'STOCKSENSE_API',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String? _runtimeOverride;
  static String? _apiKey;

  /// Backend-provided settings cached from the last /monitor/config response.
  /// Updated by [updateFromMonitorConfig] each time scenarios_screen polls.
  /// Defaults match the historical hardcoded values so first-render is sane.
  static double geminiCostPerMTok = 0.15;
  static String geminiModel = 'gemini-2.5-flash';
  static String serverVersion = '1.0.0';
  static String companyName = 'Khan Traders · Lahore';

  /// Client-side timing constants — can be tuned without a rebuild.
  static const int pollIntervalSeconds = 5;
  static const int sseTimeoutSeconds = 20;

  static String get baseUrl => _runtimeOverride ?? _envBase;

  /// Empty string means no auth header will be sent.
  static String get apiKey => _apiKey ?? '';

  /// Update cached server-side settings from a /monitor/config response.
  /// Tolerates missing fields so older backends don't break the client.
  static void updateFromMonitorConfig(Map<String, dynamic> config) {
    final cost = config['gemini_cost_per_mtok'];
    if (cost is num) geminiCostPerMTok = cost.toDouble();
    final model = config['gemini_model'];
    if (model is String && model.isNotEmpty) geminiModel = model;
    final ver = config['app_version'];
    if (ver is String && ver.isNotEmpty) serverVersion = ver;
    final name = config['company_name'];
    if (name is String && name.isNotEmpty) companyName = name;
  }

  /// Load persisted config from shared_preferences.
  /// Call this in main() before runApp().
  static Future<void> loadPersistedBase() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('api_base');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _runtimeOverride = savedUrl;
    }
    _apiKey = prefs.getString('api_key') ?? '';
  }

  /// Set and persist a new API base URL.
  static Future<void> setBaseUrl(String url) async {
    _runtimeOverride = url.trim();
    while (_runtimeOverride!.endsWith('/')) {
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

  /// Set and persist the API key.
  static Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_apiKey!.isEmpty) {
      await prefs.remove('api_key');
    } else {
      await prefs.setString('api_key', _apiKey!);
    }
  }

  /// Clear the API key.
  static Future<void> clearApiKey() async {
    _apiKey = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_key');
  }

  static String scenariosRun(String scenarioId, {bool offline = false}) =>
      offline
          ? '$baseUrl/scenarios/$scenarioId/run?offline=true'
          : '$baseUrl/scenarios/$scenarioId/run';
  static String runEvents(String runId) => '$baseUrl/runs/$runId/events';
  static String runStateDiff(String runId) => '$baseUrl/runs/$runId/state-diff';
  static String runExport(String runId) => '$baseUrl/runs/$runId/export';
  static String runDetail(String runId) => '$baseUrl/runs/$runId';
  static String latestRuns([int limit = 5]) => '$baseUrl/runs/latest?limit=$limit';
  static String monitorConfig() => '$baseUrl/monitor/config';
}
