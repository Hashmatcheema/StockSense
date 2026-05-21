/// Trace event model — mirrors backend TraceEvent.
class TraceEvent {
  final String id;
  final String runId;
  final String agentName;
  final String eventType;
  final String inputSummary;
  final String outputSummary;
  final dynamic detail;
  final int latencyMs;
  final int tokensUsed;
  final String timestamp;

  TraceEvent({
    required this.id,
    required this.runId,
    required this.agentName,
    required this.eventType,
    this.inputSummary = '',
    this.outputSummary = '',
    this.detail,
    this.latencyMs = 0,
    this.tokensUsed = 0,
    this.timestamp = '',
  });

  factory TraceEvent.fromJson(Map<String, dynamic> json) => TraceEvent(
        id: json['id'] as String? ?? '',
        runId: json['run_id'] as String? ?? '',
        agentName: json['agent_name'] as String? ?? '',
        eventType: json['event_type'] as String? ?? '',
        inputSummary: json['input_summary'] as String? ?? '',
        outputSummary: json['output_summary'] as String? ?? '',
        detail: json['detail'],
        latencyMs: json['latency_ms'] as int? ?? 0,
        tokensUsed: json['tokens_used'] as int? ?? 0,
        timestamp: json['timestamp'] as String? ?? '',
      );

}
