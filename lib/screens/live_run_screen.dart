import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/scenario.dart';
import '../models/trace_event.dart';
import '../services/api_service.dart';
import '../services/sse_service.dart';
import '../theme/app_theme.dart';
import 'before_after_screen.dart';

class LiveRunScreen extends StatefulWidget {
  final String runId;
  final Scenario scenario;

  const LiveRunScreen({super.key, required this.runId, required this.scenario});

  @override
  State<LiveRunScreen> createState() => _LiveRunScreenState();
}

class _LiveRunScreenState extends State<LiveRunScreen> with SingleTickerProviderStateMixin {
  final SseService _sse = SseService();
  final ApiService _api = ApiService();
  final List<TraceEvent> _events = [];
  final Set<int> _expanded = {};
  final Set<String> _seenIds = {};
  final ScrollController _scrollController = ScrollController();
  bool _done = false;
  int _totalTokens = 0;
  int _totalLatencyMs = 0;
  StreamSubscription<TraceEvent>? _sseSubscription;
  DateTime? _firstEventTime;
  Timer? _timeoutTimer;
  bool _showTimeout = false;

  // Action Plan (FR-6.2)
  Map<String, dynamic>? _actionPlan;
  bool _actionPlanExpanded = false;

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _connectSSE();
    // Start timeout timer for empty state
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _events.isEmpty) {
        setState(() => _showTimeout = true);
      }
    });
  }

  void _connectSSE() {
    final stream = _sse.connect(widget.runId);
    _sseSubscription = stream.listen(
      (event) {
        if (mounted) {
          // Deduplicate by event ID (A2 fix)
          if (!_seenIds.add(event.id)) return;

          setState(() {
            _events.add(event);
            _totalTokens += event.tokensUsed;
            _totalLatencyMs += event.latencyMs;
            _firstEventTime ??= DateTime.now();
            _showTimeout = false;

            // Check for plan_generated to fetch action plan (FR-6.2)
            if (event.eventType == 'plan_generated') {
              _fetchActionPlan();
            }
          });

          // Auto-scroll to newest event
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _done = true);
          // Fetch action plan on completion if we haven't already
          if (_actionPlan == null) _fetchActionPlan();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _done = true);
      },
    );
  }

  Future<void> _fetchActionPlan() async {
    // Prefer structured plan from state-diff (already parsed server-side)
    final diff = await _api.getStateDiff(widget.runId);
    if (diff?.actionPlan != null && mounted) {
      setState(() => _actionPlan = diff!.actionPlan);
      return;
    }
    // Fall back to run detail for in-progress runs where state-diff isn't ready
    final detail = await _api.getRunDetail(widget.runId);
    if (detail != null && mounted) {
      final run = detail['run'];
      if (run != null) {
        final planJson = run['action_plan'];
        if (planJson != null) {
          Map<String, dynamic>? plan;
          if (planJson is String) {
            try {
              plan = jsonDecode(planJson) as Map<String, dynamic>?;
            } catch (_) {}
          } else if (planJson is Map) {
            plan = planJson as Map<String, dynamic>;
          }
          if (plan != null && mounted) {
            setState(() => _actionPlan = plan);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseCtrl.dispose();
    _scrollController.dispose();
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sse.disconnect();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Run — ${widget.scenario.id}',
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(widget.scenario.title,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          if (_done)
            TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined, color: AppColors.actionPrimary, size: 18),
              label: Text('View Results',
                  style: GoogleFonts.inter(color: AppColors.actionPrimary, fontSize: 13)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    BeforeAfterScreen(runId: widget.runId, scenario: widget.scenario),
              )),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildStatsBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    const kCostPerMTok = 0.30;
    final costUsd = _totalTokens / 1000000 * kCostPerMTok;

    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildStat('LATENCY', '${_totalLatencyMs}ms'),
          const SizedBox(width: 16),
          _buildStat('TOKENS', '$_totalTokens'),
          const SizedBox(width: 16),
          _buildStat('COST', '\$${costUsd.toStringAsFixed(4)}'),
          const Spacer(),
          Text(
            _done ? 'COMPLETE' : 'RUNNING',
            style: TextStyle(
              color: _done
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF6B7280), fontSize: 9, letterSpacing: 0.5)),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFF9FAFB),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBody() {
    if (_showTimeout && _events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('Backend not reachable',
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Check your API URL in Settings',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Open Settings'),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.actionPrimary,
                side: const BorderSide(color: AppColors.actionPrimary),
              ),
            ),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: (_actionPlan != null ? 1 : 0) + _events.length,
      itemBuilder: (ctx, i) {
        if (_actionPlan != null && i == 0) {
          return _buildActionPlanCard();
        }
        final eventIdx = _actionPlan != null ? i - 1 : i;
        final event = _events[eventIdx];
        if (event.outputSummary.isEmpty &&
            event.inputSummary.isEmpty &&
            (event.detail == null || event.detail.toString() == '{}')) {
          return const SizedBox.shrink();
        }
        return _TraceEventRow(
          event: event,
          firstEventTime: _firstEventTime,
          isExpanded: _expanded.contains(eventIdx),
          onToggle: () => setState(() {
            _expanded.contains(eventIdx)
                ? _expanded.remove(eventIdx)
                : _expanded.add(eventIdx);
          }),
        );
      },
    );
  }

  Widget _buildActionPlanCard() {
    final actions = (_actionPlan?['actions'] as List<dynamic>?) ?? [];
    final totalImpact = _actionPlan?['total_estimated_impact_pkr'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _actionPlanExpanded = !_actionPlanExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      color: AppColors.actionPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Action Plan · ${actions.length} steps · Rs ${_formatNumber(totalImpact)} impact',
                        style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(
                    _actionPlanExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_actionPlanExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: actions.asMap().entries.map((e) {
                  final idx = e.key;
                  final a = e.value as Map<String, dynamic>;
                  final deps = (a['depends_on'] as List<dynamic>?) ?? [];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text('${idx + 1}.',
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted, fontSize: 12)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(a['kind'] ?? '',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10, color: AppColors.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a['rationale'] ?? '',
                                  style: GoogleFonts.inter(
                                      color: AppColors.textSecondary, fontSize: 12)),
                              if (deps.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                      '↳ depends on ${deps.map((d) { final s = d.toString(); return s.length > 8 ? "${s.substring(0, 8)}…" : s; }).join(", ")}',
                                      style: GoogleFonts.inter(
                                          color: AppColors.textMuted,
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatNumber(dynamic n) {
    if (n == null) return '0';
    final num value = n is num ? n : num.tryParse(n.toString()) ?? 0;
    if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }
}

class _TraceEventRow extends StatelessWidget {
  final TraceEvent event;
  final DateTime? firstEventTime;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _TraceEventRow({
    required this.event,
    required this.firstEventTime,
    required this.isExpanded,
    required this.onToggle,
  });

  String get _wallClock {
    try {
      final ts = DateTime.parse(event.timestamp);
      final mm = ts.minute.toString().padLeft(2, '0');
      final ss = ts.second.toString().padLeft(2, '0');
      final ms = ts.millisecond.toString().padLeft(3, '0');
      return '$mm:$ss.$ms';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.eventColor(event.eventType);

    final subtitle = event.outputSummary.isNotEmpty
        ? event.outputSummary
        : event.inputSummary.isNotEmpty
            ? event.inputSummary
            : event.eventType;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: borderColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppColors.agentIcon(event.agentName),
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(event.agentName,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(event.eventType,
                                style: GoogleFonts.inter(
                                    fontSize: 10, color: AppColors.textSecondary)),
                          ),
                          const Spacer(),
                          Text(_wallClock,
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textSecondary)),
                      if (isExpanded && event.detail != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDetail(event.detail),
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
