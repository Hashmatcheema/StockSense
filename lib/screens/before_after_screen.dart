import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scenario.dart';
import '../models/state_diff.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class BeforeAfterScreen extends StatefulWidget {
  final String runId;
  final Scenario scenario;

  const BeforeAfterScreen({super.key, required this.runId, required this.scenario});

  @override
  State<BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends State<BeforeAfterScreen> {
  final ApiService _api = ApiService();
  StateDiff? _diff;
  Map<String, dynamic>? _runDetail;
  bool _loading = true;
  bool _error = false;
  bool _isInProgress = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // #22: Fetch both in parallel — they hit different endpoints.
      final results = await Future.wait([
        _api.getStateDiff(widget.runId),
        _api.getRunDetail(widget.runId),
      ]);
      final diff = results[0] as StateDiff?;
      final detail = results[1] as Map<String, dynamic>?;
      // #24: Distinguish "run still in progress" (diff not ready yet) from
      // a real network/parse failure (diff null AND run is completed/failed).
      final phase = (detail?['run'] as Map<String, dynamic>?)?['phase'] as String?;
      final runFinished = phase == 'completed' || phase == 'failed';
      if (mounted) {
        setState(() {
          _diff = diff;
          _runDetail = detail;
          _loading = false;
          _isInProgress = diff == null && !runFinished;
          _error = diff == null && runFinished;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _exportTrace() async {
    setState(() => _exporting = true);
    try {
      final jsonStr = await _api.downloadTraceJson(widget.runId);
      if (jsonStr != null) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/trace_${widget.runId}.json');
        await file.writeAsString(jsonStr);
        await Share.shareXFiles([XFile(file.path)], subject: 'StockSense Trace Export');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download trace'), backgroundColor: AppColors.stateCritical));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: AppColors.stateCritical));
      }
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  void dispose() {
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
        title: Text('Before / After — ${widget.scenario.id}',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary))
          : (_error || _isInProgress || _diff == null)
              ? _buildErrorState()
              : _buildContent(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildErrorState() {
    // #24: Show different copy depending on whether the run is in-progress or
    // a real network/parse failure occurred.
    final isInProg = _isInProgress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInProg ? Icons.hourglass_empty_outlined : Icons.error_outline,
            color: isInProg ? AppColors.textMuted : AppColors.stateCritical,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isInProg ? 'Run still in progress' : 'Failed to load results',
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            isInProg
                ? 'Results will appear once the pipeline completes'
                : 'Check your connection and try again',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isInProg)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    onPressed: () {
                      setState(() { _loading = true; _error = false; _isInProgress = false; });
                      _load();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.actionPrimary,
                      side: const BorderSide(color: AppColors.actionPrimary),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.actionPrimary,
                  side: const BorderSide(color: AppColors.actionPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricGrid(),
          const SizedBox(height: 24),
          _buildSectionHeader('Actions Taken', Icons.bolt_outlined),
          const SizedBox(height: 8),
          _buildActionsTaken(),
          const SizedBox(height: 24),
          _buildSectionHeader('Customer ETAs', Icons.schedule_outlined),
          const SizedBox(height: 8),
          _buildCustomerEtas(),
          const SizedBox(height: 24),
          _buildSectionHeader('Agent Summary', Icons.hub_outlined),
          const SizedBox(height: 8),
          _buildAgentTraceSummary(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(title,
            style: GoogleFonts.inter(
                color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _formatPkr(num value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }

  Widget _buildMetricGrid() {
    final d = _diff!;

    final bRisk = d.before.riskMetrics.stockoutRiskPct;
    final aRisk = d.after.riskMetrics.stockoutRiskPct;
    final riskDelta = aRisk - bRisk;

    final bRev = d.before.riskMetrics.revenueAtRiskPkr;
    final aRev = d.after.riskMetrics.revenueAtRiskPkr;
    final revDelta = aRev - bRev;

    final bDays = d.before.riskMetrics.daysOfStockRemaining;
    final aDays = d.after.riskMetrics.daysOfStockRemaining;
    final daysDelta = aDays - bDays;

    final bOrders = d.before.riskMetrics.pendingCustomerOrdersAffected;
    final aOrders = d.after.riskMetrics.pendingCustomerOrdersAffected;
    final ordersDelta = aOrders - bOrders;

    // Pick the supplier whose status changed; fall back to worst status (silent > delayed > active)
    String bStatus = 'active';
    String aStatus = 'active';
    String? pickSupplier() {
      for (final k in d.before.supplierStatus.keys) {
        if (d.before.supplierStatus[k] != d.after.supplierStatus[k]) return k;
      }
      const rank = {'silent': 2, 'delayed': 1, 'active': 0};
      String? worst;
      int worstRank = -1;
      for (final entry in d.after.supplierStatus.entries) {
        final r = rank[entry.value] ?? 0;
        if (r > worstRank) { worstRank = r; worst = entry.key; }
      }
      return worst ?? (d.after.supplierStatus.isNotEmpty ? d.after.supplierStatus.keys.first : null);
    }
    final supplierKey = pickSupplier();
    if (supplierKey != null) {
      bStatus = d.before.supplierStatus[supplierKey] ?? 'active';
      aStatus = d.after.supplierStatus[supplierKey] ?? 'active';
    }

    final notifCount = d.changesSummary['notifications_added'] ?? 0;

    // Determine largest absolute change for highlight
    final deltas = <String, double>{
      'risk': riskDelta.abs(),
      'rev': revDelta.abs(),
      'days': daysDelta.abs().toDouble(),
      'orders': ordersDelta.abs().toDouble(),
    };
    final maxDelta = deltas.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    // Responsive grid: phone = 2 cols, tablet/landscape = 3, desktop = 4.
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1100 ? 4 : (width >= 700 ? 3 : 2);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cols,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.3,
      children: [
        _MetricCard(
          icon: Icons.warning_amber_rounded,
          label: 'STOCKOUT RISK',
          before: '${bRisk.toStringAsFixed(0)}%',
          after: '${aRisk.toStringAsFixed(0)}%',
          afterColor: AppColors.riskColor(aRisk),
          delta: '${riskDelta < 0 ? '▼' : '▲'} ${riskDelta.abs().toStringAsFixed(0)}pp',
          deltaPositive: riskDelta < 0,
          highlighted: maxDelta == 'risk',
        ),
        _MetricCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'REVENUE AT RISK',
          before: 'Rs ${_formatPkr(bRev)}',
          after: 'Rs ${_formatPkr(aRev)}',
          afterColor: aRev > 0 ? AppColors.stateWarn : AppColors.stateOk,
          delta: '${revDelta <= 0 ? '▼' : '▲'} Rs ${_formatPkr(revDelta.abs())}',
          deltaPositive: revDelta <= 0,
          highlighted: maxDelta == 'rev',
        ),
        _MetricCard(
          icon: Icons.event_available_outlined,
          label: 'DAYS OF STOCK',
          before: '$bDays days',
          after: '$aDays days',
          afterColor: aDays > 5 ? AppColors.stateOk : AppColors.stateWarn,
          delta: '${daysDelta > 0 ? '▲' : '▼'} ${daysDelta.abs()} days',
          deltaPositive: daysDelta > 0,
          highlighted: maxDelta == 'days',
        ),
        _MetricCard(
          icon: Icons.local_shipping_outlined,
          label: 'AFFECTED ORDERS',
          before: '$bOrders',
          after: '$aOrders',
          afterColor: aOrders == 0 ? AppColors.stateOk : AppColors.stateWarn,
          delta: '${ordersDelta <= 0 ? '▼' : '▲'} ${ordersDelta.abs()}',
          deltaPositive: ordersDelta <= 0,
          highlighted: maxDelta == 'orders',
        ),
        _MetricCard(
          icon: Icons.local_shipping_outlined,
          label: 'SUPPLIER STATUS',
          before: bStatus,
          after: aStatus,
          afterColor: AppColors.supplierColor(aStatus),
          delta: bStatus == aStatus ? '—' : '$bStatus → $aStatus',
          deltaPositive: aStatus == 'active',
          highlighted: false,
        ),
        _MetricCard(
          icon: Icons.notifications_outlined,
          label: 'NOTIFICATIONS',
          before: '${d.before.notificationQueue.length}',
          after: '${d.after.notificationQueue.length}',
          afterColor: notifCount > 0 ? AppColors.stateInfo : AppColors.textMuted,
          delta: notifCount > 0 ? '+$notifCount sent' : '—',
          deltaPositive: true,
          highlighted: false,
        ),
      ],
    );
  }

  Widget _buildActionsTaken() {
    final actions = _diff?.actionsTaken ?? [];

    if (actions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('No actions executed',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions.asMap().entries.map((e) {
          final idx = e.key;
          final a = e.value;
          return Padding(
            padding: EdgeInsets.only(bottom: idx < actions.length - 1 ? 10 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text('${idx + 1}.',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(a.kind,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(a.rationale,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCustomerEtas() {
    final etas = _diff?.changesSummary['customer_etas'] as Map<String, dynamic>?;

    if (etas == null || etas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('No ETA changes',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      );
    }

    final ordersShifted = etas['orders_shifted'] ?? 0;
    final avgDays = etas['avg_days_shifted'] ?? 0;
    final examples = (etas['examples'] as List<dynamic>?) ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 14, color: AppColors.stateWarn),
              const SizedBox(width: 6),
              Text('$ordersShifted orders shifted by ~$avgDays days',
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          if (examples.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...examples.map((ex) {
              final e = ex as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text(e['order_id'] ?? '',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Text('${e['before']} → ${e['after']}',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                    const Spacer(),
                    StatusPill(
                      label: '+${e['days_shifted'] ?? 0}d',
                      color: AppColors.stateWarn,
                      tint: AppColors.tintWarn,
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentTraceSummary() {
    final events = _runDetail?['trace_events'] as List<dynamic>? ?? [];

    final Map<String, Map<String, dynamic>> agentStats = {
      'ingestion': {'count': 0, 'latency': 0},
      'insight': {'count': 0, 'latency': 0},
      'planner': {'count': 0, 'latency': 0},
      'executor': {'count': 0, 'latency': 0},
      'supervisor': {'count': 0, 'latency': 0},
    };

    for (var ev in events) {
      final name = ev['agent_name'] as String;
      if (agentStats.containsKey(name)) {
        agentStats[name]!['count'] = (agentStats[name]!['count'] as int) + 1;
        agentStats[name]!['latency'] =
            (agentStats[name]!['latency'] as int) + (ev['latency_ms'] as int? ?? 0);
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: agentStats.entries.map((e) {
          final stat = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: e.key != agentStats.keys.last
                  ? const Border(bottom: BorderSide(color: AppColors.border))
                  : null,
            ),
            child: Row(
              children: [
                Icon(AppColors.agentIcon(e.key), size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(e.key,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500))),
                Text('${stat['count']} events',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 16),
                Text('${stat['latency']}ms',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : _exportTrace,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
                  : const Icon(Icons.file_download_outlined, size: 16, color: AppColors.textSecondary),
              label: Text(_exporting ? 'Exporting...' : 'Export Trace',
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.actionPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              child: Text('Back to Scenarios',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String before;
  final String after;
  final Color afterColor;
  final String delta;
  final bool deltaPositive;
  final bool highlighted;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.before,
    required this.after,
    required this.afterColor,
    required this.delta,
    required this.deltaPositive,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = highlighted
        ? (deltaPositive ? AppColors.tintOk : AppColors.tintCritical)
        : AppColors.surface;
    // When the card is already tinted, use a semi-transparent white badge
    // so the delta tag doesn't double-stack the same tint.
    final badgeColor = highlighted
        ? Colors.white.withOpacity(0.55)
        : (deltaPositive ? AppColors.tintOk : AppColors.tintCritical);

    return Semantics(
      label: '$label: was $before, now $after, $delta',
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('$before→$after'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(before,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough),
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    const Icon(Icons.arrow_forward, size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(after,
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: afterColor),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(delta,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    color: deltaPositive ? AppColors.stateOk : AppColors.stateCritical,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
    );
  }
}
