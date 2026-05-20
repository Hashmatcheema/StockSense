import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/api_config.dart';
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
  final Set<String> _expanded = {};
  final Set<String> _seenIds = {};
  final ScrollController _scrollController = ScrollController();
  bool _done = false;
  int _totalTokens = 0;
  int _totalLatencyMs = 0;
  StreamSubscription<TraceEvent>? _sseSubscription;
  Timer? _timeoutTimer;
  bool _showTimeout = false;

  // Batched SSE event flush — coalesces bursts into ≤4 setStates/sec.
  final List<TraceEvent> _pendingEvents = [];
  Timer? _flushTimer;
  bool _shouldAutoScroll = true;

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
    _timeoutTimer = Timer(Duration(seconds: ApiConfig.sseTimeoutSeconds), () {
      if (mounted && _events.isEmpty) {
        setState(() => _showTimeout = true);
      }
    });
  }

  void _retryConnection() {
    HapticFeedback.selectionClick();
    _sseSubscription?.cancel();
    _sse.disconnect();
    setState(() {
      _showTimeout = false;
      _done = false;
    });
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(seconds: ApiConfig.sseTimeoutSeconds), () {
      if (mounted && _events.isEmpty) {
        setState(() => _showTimeout = true);
      }
    });
    _connectSSE();
  }

  void _connectSSE() {
    final stream = _sse.connect(widget.runId);
    _sseSubscription = stream.listen(
      (event) {
        if (!mounted) return;
        // Deduplicate by event ID (A2 fix)
        if (!_seenIds.add(event.id)) return;
        _pendingEvents.add(event);
        if (event.eventType == 'plan_generated') {
          _fetchActionPlan();
        }
        _flushTimer ??= Timer(const Duration(milliseconds: 250), _flushPending);
      },
      onDone: () {
        _flushPending();
        if (mounted) {
          setState(() => _done = true);
          if (_actionPlan == null) _fetchActionPlan();
        }
      },
      onError: (_) {
        _flushPending();
        if (mounted) setState(() => _done = true);
      },
    );
  }

  void _flushPending() {
    _flushTimer = null;
    if (!mounted || _pendingEvents.isEmpty) return;
    final batch = List<TraceEvent>.from(_pendingEvents);
    _pendingEvents.clear();
    setState(() {
      for (final e in batch) {
        _events.add(e);
        _totalTokens += e.tokensUsed;
        _totalLatencyMs += e.latencyMs;
      }
      _showTimeout = false;
    });
    if (_shouldAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
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
    _flushTimer?.cancel();
    _flushTimer = null;
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
        backgroundColor: AppColors.surface,
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
    // Cost rate is fetched from /monitor/config and cached in ApiConfig so
    // it matches the actual backend billing rate without a client rebuild.
    final costUsd = _totalTokens / 1000000 * ApiConfig.geminiCostPerMTok;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
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
              color: _done ? AppColors.stateOk : AppColors.stateWarn,
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
            style: GoogleFonts.jetBrainsMono(
                color: AppColors.textMuted, fontSize: 9, letterSpacing: 0.5)),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                color: AppColors.textPrimary,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  onPressed: _retryConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.actionPrimary,
                    side: const BorderSide(color: AppColors.actionPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Open Settings'),
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary));
    }

    // Filter out empty events, then group consecutive same-agent/type events.
    final visibleEvents = _events.where((e) =>
        e.outputSummary.isNotEmpty ||
        e.inputSummary.isNotEmpty ||
        (e.detail != null && e.detail.toString() != '{}')).toList();

    final groups = <List<TraceEvent>>[];
    for (final e in visibleEvents) {
      if (groups.isNotEmpty &&
          groups.last.first.agentName == e.agentName &&
          groups.last.first.eventType == e.eventType) {
        groups.last.add(e);
      } else {
        groups.add([e]);
      }
    }

    DateTime? firstTs;
    if (_events.isNotEmpty) {
      try { firstTs = DateTime.parse(_events.first.timestamp); } catch (_) {}
    }

    final itemCount = (_actionPlan != null ? 1 : 0) + groups.length;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (_actionPlan != null && i == 0) return _buildActionPlanCard();
        final gi = _actionPlan != null ? i - 1 : i;
        final group = groups[gi];

        if (group.length == 1) {
          final event = group[0];
          return _TraceEventRow(
            key: ValueKey(event.id),
            event: event,
            firstEventTimestamp: firstTs,
            isExpanded: _expanded.contains(event.id),
            onToggle: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded.contains(event.id)
                  ? _expanded.remove(event.id)
                  : _expanded.add(event.id));
            },
          );
        }

        // Grouped: show summary card with expand-to-see-all
        final groupKey = 'group:${group[0].id}';
        final isGroupExpanded = _expanded.contains(groupKey);
        return _GroupedEventRow(
          key: ValueKey(groupKey),
          events: group,
          firstEventTimestamp: firstTs,
          isExpanded: isGroupExpanded,
          expandedItems: _expanded,
          onToggleGroup: () {
            HapticFeedback.selectionClick();
            setState(() => isGroupExpanded
                ? _expanded.remove(groupKey)
                : _expanded.add(groupKey));
          },
          onToggleItem: (id) {
            HapticFeedback.selectionClick();
            setState(() => _expanded.contains(id)
                ? _expanded.remove(id)
                : _expanded.add(id));
          },
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

String _elapsedLabel(String timestamp, DateTime? firstTs) {
  if (firstTs == null) return '';
  try {
    final ts = DateTime.parse(timestamp);
    final ms = ts.difference(firstTs).inMilliseconds.clamp(0, 999999);
    if (ms < 1000) return '+${ms}ms';
    return '+${(ms / 1000).toStringAsFixed(1)}s';
  } catch (_) {
    return '';
  }
}

String _cleanSummary(String summary) {
  // Strip long Windows/Unix file paths — keep the human-readable part.
  return summary.replaceAllMapped(
    RegExp(r'from [A-Z]:\\[^\s,]+|from /[^\s,]+'),
    (m) => '',
  ).trim();
}

class _TraceEventRow extends StatelessWidget {
  final TraceEvent event;
  final DateTime? firstEventTimestamp;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _TraceEventRow({
    super.key,
    required this.event,
    required this.firstEventTimestamp,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.eventColor(event.eventType);
    final rawSubtitle = event.outputSummary.isNotEmpty
        ? event.outputSummary
        : event.inputSummary.isNotEmpty
            ? event.inputSummary
            : event.eventType;
    final subtitle = _cleanSummary(rawSubtitle);
    final elapsed = _elapsedLabel(event.timestamp, firstEventTimestamp);

    return Semantics(
      label: '${event.agentName}: ${event.eventType} — $subtitle',
      button: true,
      child: GestureDetector(
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
                            Text(elapsed,
                                style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
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

/// Collapsed summary card for consecutive same-agent/type events.
class _GroupedEventRow extends StatelessWidget {
  final List<TraceEvent> events;
  final DateTime? firstEventTimestamp;
  final bool isExpanded;
  final Set<String> expandedItems;
  final VoidCallback onToggleGroup;
  final void Function(String id) onToggleItem;

  const _GroupedEventRow({
    super.key,
    required this.events,
    required this.firstEventTimestamp,
    required this.isExpanded,
    required this.expandedItems,
    required this.onToggleGroup,
    required this.onToggleItem,
  });

  @override
  Widget build(BuildContext context) {
    final first = events.first;
    final borderColor = AppColors.eventColor(first.eventType);
    final elapsed = _elapsedLabel(first.timestamp, firstEventTimestamp);

    // Build a one-line summary of what the group contains.
    final summaries = events.map((e) {
      final raw = e.outputSummary.isNotEmpty ? e.outputSummary : e.inputSummary;
      return _cleanSummary(raw);
    }).where((s) => s.isNotEmpty).toList();

    // Find the common prefix, or just show the count
    String groupSummary;
    if (summaries.length == events.length) {
      // e.g. "source_accepted ×5" with first item's summary
      groupSummary = summaries.first;
    } else {
      groupSummary = first.eventType;
    }

    return Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group header — tap to expand/collapse
                  InkWell(
                    onTap: onToggleGroup,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Icon(AppColors.agentIcon(first.agentName),
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(first.agentName,
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
                            child: Text(first.eventType,
                                style: GoogleFonts.inter(
                                    fontSize: 10, color: AppColors.textSecondary)),
                          ),
                          const SizedBox(width: 6),
                          // Count badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: borderColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('×${events.length}',
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: borderColor,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const Spacer(),
                          Text(elapsed,
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10, color: AppColors.textMuted)),
                          const SizedBox(width: 6),
                          Icon(
                            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Summary line when collapsed
                  if (!isExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Text(groupSummary,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  // Individual items when expanded
                  if (isExpanded)
                    ...events.map((e) {
                      final rawSub = e.outputSummary.isNotEmpty ? e.outputSummary : e.inputSummary;
                      final sub = _cleanSummary(rawSub);
                      final itemElapsed = _elapsedLabel(e.timestamp, firstEventTimestamp);
                      final isItemExpanded = expandedItems.contains(e.id);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1, color: AppColors.border),
                          InkWell(
                            onTap: () => onToggleItem(e.id),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(sub,
                                        style: GoogleFonts.inter(
                                            fontSize: 12, color: AppColors.textSecondary),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(itemElapsed,
                                      style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ),
                          if (isItemExpanded && e.detail != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _formatDetail(e.detail),
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                ],
              ),
            ),
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
