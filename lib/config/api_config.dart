class ApiConfig {
  static String get baseUrl {
    return 'http://localhost:8000';
  }

  static String scenariosRun(String scenarioId) =>
      '$baseUrl/scenarios/$scenarioId/run';
  static String runEvents(String runId) => '$baseUrl/runs/$runId/events';
  static String runStateDiff(String runId) => '$baseUrl/runs/$runId/state-diff';
  static String runExport(String runId) => '$baseUrl/runs/$runId/export';
  static String runDetail(String runId) => '$baseUrl/runs/$runId';
}
