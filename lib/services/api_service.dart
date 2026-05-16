import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/state_diff.dart';

/// HTTP client for StockSense REST API.
class ApiService {
  final http.Client _client = http.Client();

  /// POST /scenarios/{id}/run — start a run.
  Future<String?> startRun(String scenarioId) async {
    try {
      final resp = await _client.post(Uri.parse(ApiConfig.scenariosRun(scenarioId)));
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
      final resp = await _client.get(Uri.parse(ApiConfig.runDetail(runId)));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// GET /runs/{runId}/state-diff — get before/after.
  Future<StateDiff?> getStateDiff(String runId) async {
    try {
      final resp = await _client.get(Uri.parse(ApiConfig.runStateDiff(runId)));
      if (resp.statusCode == 200) {
        return StateDiff.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}
