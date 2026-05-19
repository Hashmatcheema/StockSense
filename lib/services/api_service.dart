import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/state_diff.dart';

/// HTTP client for StockSense REST API.
class ApiService {
  final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 5);

  /// POST /scenarios/{id}/run — start a run.
  Future<String?> startRun(String scenarioId) async {
    try {
      final resp = await _client.post(Uri.parse(ApiConfig.scenariosRun(scenarioId))).timeout(_timeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['run_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// GET /runs/{runId} — get full run details.
  Future<Map<String, dynamic>?> getRunDetail(String runId) async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.runDetail(runId))).timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// GET /runs/{runId}/state-diff — get before/after.
  Future<StateDiff?> getStateDiff(String runId) async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.runStateDiff(runId))).timeout(_timeout);
      if (resp.statusCode == 200) {
        return StateDiff.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// GET /runs/latest?limit=N — get recent runs.
  Future<List<dynamic>?> getLatestRuns([int limit = 5]) async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.latestRuns(limit))).timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as List<dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// GET /monitor/config
  Future<Map<String, dynamic>?> getMonitorConfig() async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.monitorConfig())).timeout(_timeout);
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// PUT /monitor/config
  Future<bool> setMonitorConfig(int intervalSeconds) async {
    try {
      final resp = await _client.put(
        Uri.parse(ApiConfig.monitorConfig()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'interval_seconds': intervalSeconds}),
      ).timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// GET /runs/{runId}/export — download trace JSON as string.
  Future<String?> downloadTraceJson(String runId) async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.runExport(runId))).timeout(_timeout);
      if (resp.statusCode == 200) {
        return resp.body;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}
