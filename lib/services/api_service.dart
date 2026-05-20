import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/state_diff.dart';
import 'error_bus.dart';

/// HTTP client for StockSense REST API.
///
/// Errors are reported via [ErrorBus] (silent by default — these endpoints
/// are polled and we don't want to spam the user). Callers that need a
/// user-visible failure should treat `null` returns as a failure signal and
/// surface their own UI (see scenarios_screen `_loadError`, live_run timeout).
///
/// The underlying [http.Client] is a process-wide singleton so connection
/// keep-alive works correctly. Each ApiService instance is now a thin
/// stateless facade over that one client. `dispose()` is intentionally a
/// no-op — closing the client from one screen would break sibling screens.
class ApiService {
  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 5);

  Map<String, String> get _headers {
    final key = ApiConfig.apiKey;
    if (key.isNotEmpty) return {'X-API-Key': key};
    return const {};
  }

  /// POST /scenarios/{id}/run — start a run.
  Future<String?> startRun(String scenarioId, {bool offline = false}) async {
    try {
      final resp = await _client
          .post(Uri.parse(ApiConfig.scenariosRun(scenarioId, offline: offline)),
              headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['run_id'] as String?;
      }
      ErrorBus.report('HTTP ${resp.statusCode}', context: 'startRun', silent: true);
    } catch (e) {
      ErrorBus.report(e, context: 'startRun', silent: true);
    }
    return null;
  }

  /// GET /runs/{runId} — get full run details.
  Future<Map<String, dynamic>?> getRunDetail(String runId) async {
    try {
      final resp = await _client
          .get(Uri.parse(ApiConfig.runDetail(runId)), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      ErrorBus.report(e, context: 'getRunDetail', silent: true);
    }
    return null;
  }

  /// GET /runs/{runId}/state-diff — get before/after.
  Future<StateDiff?> getStateDiff(String runId) async {
    try {
      final resp = await _client
          .get(Uri.parse(ApiConfig.runStateDiff(runId)), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return StateDiff.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      ErrorBus.report(e, context: 'getStateDiff', silent: true);
    }
    return null;
  }

  /// GET /runs/latest?limit=N — get recent runs.
  Future<List<dynamic>?> getLatestRuns([int limit = 5]) async {
    try {
      final resp = await _client
          .get(Uri.parse(ApiConfig.latestRuns(limit)), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as List<dynamic>;
      }
    } catch (e) {
      ErrorBus.report(e, context: 'getLatestRuns', silent: true);
    }
    return null;
  }

  /// GET /monitor/config
  Future<Map<String, dynamic>?> getMonitorConfig() async {
    try {
      final resp = await _client
          .get(Uri.parse(ApiConfig.monitorConfig()), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      ErrorBus.report(e, context: 'getMonitorConfig', silent: true);
    }
    return null;
  }

  /// PUT /monitor/config
  Future<bool> setMonitorConfig(int intervalSeconds) async {
    try {
      final resp = await _client.put(
        Uri.parse(ApiConfig.monitorConfig()),
        headers: {'Content-Type': 'application/json', ..._headers},
        body: jsonEncode({'interval_seconds': intervalSeconds}),
      ).timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      ErrorBus.report(e, context: 'setMonitorConfig', silent: true);
    }
    return false;
  }

  /// GET /runs/{runId}/export — download trace JSON as string.
  Future<String?> downloadTraceJson(String runId) async {
    try {
      final resp = await _client
          .get(Uri.parse(ApiConfig.runExport(runId)), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return resp.body;
      }
    } catch (e) {
      ErrorBus.report(e, context: 'downloadTraceJson', silent: true);
    }
    return null;
  }

  /// No-op: the underlying client is a static singleton shared across all
  /// screens. Kept for API compatibility — call sites still invoke this in
  /// their `dispose()` methods.
  void dispose() {}
}
