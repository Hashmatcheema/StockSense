import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../models/trace_event.dart';
import '../services/api_service.dart';
import '../services/sse_service.dart';
import 'before_after_screen.dart';

/// Live Run screen — renders streamed agent trace events (FR-6.2, FR-6.4, FR-6.5).
class LiveRunScreen extends StatefulWidget {
  final String runId;
  final Scenario scenario;

  const LiveRunScreen({super.key, required this.runId, required this.scenario});

  @override
  State<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends State<LiveRunScreen> {
  final SseService _sse = SseService();
  final ApiService _api = ApiService();
  final List<TraceEvent> _events = [];
  final Set<int> _expanded = {};
  bool _done = false;
  int _totalTokens = 0;
  int _totalLatencyMs = 0;

  @override
  void initState() {
    super.initState();
    _connectSSE();
  }

  void _connectSSE() {
    final stream = _sse.connect(widget.runId);
    stream.listen(
      (event) {
        if (mounted) {
          setState(() {
            _events.add(event);
            _totalTokens += event.tokensUsed;
            _totalLatencyMs += event.latencyMs;
          });
        }
      },
      onDone: () { if (mounted) setState(() => _done = true); },
      onError: (_) { if (mounted) setState(() => _done = true); },
    );
  }

  @override
  void dispose() { _sse.disconnect(); _api.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1329),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Run — ${widget.scenario.id}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(widget.scenario.title,
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        actions: [
          if (_done)
            IconButton(
              icon: const Icon(Icons.compare_arrows, color: Color(0xFF00BFA6)),
              tooltip: 'View Before/After',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BeforeAfterScreen(runId: widget.runId, scenario: widget.scenario),
              )),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsBar(),
          Expanded(child: _buildEventList()),
          if (_done) _buildCompleteBanner(),
        ],
      ),
    );
  }

  /// Live token cost and latency counters (FR-6.5).
  Widget _buildStatsBar() {
    final costUsd = _totalTokens * 0.000001; // rough estimate
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1329),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1F38))),
      ),
      child: Row(
        children: [
          _statChip(Icons.timer, '${_totalLatencyMs}ms', 'Latency'),
          const SizedBox(width: 16),
          _statChip(Icons.token, '$_totalTokens', 'Tokens'),
          const SizedBox(width: 16),
          _statChip(Icons.attach_money, '\$${costUsd.toStringAsFixed(4)}', 'Cost'),
          const Spacer(),
          if (!_done) _pulsingDot(),
          if (!_done) const SizedBox(width: 8),
          Text(_done ? 'Complete' : 'Running...',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: _done ? const Color(0xFF00BFA6) : Colors.amber)),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.white38),
      const SizedBox(width: 4),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    ]);
  }

  Widget _pulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (_, val, child) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: val),
          shape: BoxShape.circle,
        ),
      ),
      onEnd: () {}, // continuous via rebuild
    );
  }

  Widget _buildEventList() {
    if (_events.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Color(0xFF00BFA6)),
          const SizedBox(height: 16),
          Text('Waiting for agent events...',
            style: TextStyle(color: Colors.white54)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (ctx, i) => _TraceEventRow(
        event: _events[i],
        index: i,
        isExpanded: _expanded.contains(i),
        onToggle: () => setState(() {
          _expanded.contains(i) ? _expanded.remove(i) : _expanded.add(i);
        }),
      ),
    );
  }

  Widget _buildCompleteBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00BFA6), Color(0xFF00897B)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 8),
          Text('Run complete — tap to view results',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Trace Event Row (FR-6.4 — expandable) ──────────────────────────────────────

class _TraceEventRow extends StatelessWidget {
  final TraceEvent event;
  final int index;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _TraceEventRow({
    required this.event, required this.index,
    required this.isExpanded, required this.onToggle,
  });

  Color get _agentColor {
    switch (event.agentName) {
      case 'supervisor': return const Color(0xFF00BFA6);
      case 'ingestion': return const Color(0xFF42A5F5);
      case 'insight': return const Color(0xFFAB47BC);
      case 'planner': return const Color(0xFFFFA726);
      case 'executor': return const Color(0xFFEF5350);
      default: return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141830),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? _agentColor.withValues(alpha: 0.5) : const Color(0xFF1E2345),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 4, height: 32,
                decoration: BoxDecoration(
                  color: _agentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('${event.eventIcon} ', style: const TextStyle(fontSize: 14)),
                      Text(event.agentLabel,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _agentColor)),
                      const Spacer(),
                      Text(event.eventType,
                        style: TextStyle(fontSize: 11, color: Colors.white38)),
                    ]),
                    const SizedBox(height: 4),
                    if (event.outputSummary.isNotEmpty)
                      Text(event.outputSummary,
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    if (event.inputSummary.isNotEmpty && event.outputSummary.isEmpty)
                      Text(event.inputSummary,
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
              ),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white24, size: 20),
            ]),
            // Expandable detail JSON (FR-6.4)
            if (isExpanded && event.detail != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E21),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatDetail(event.detail),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white54),
                  maxLines: 20,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDetail(dynamic detail) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(detail);
    } catch (_) {
      return detail.toString();
    }
  }
}
