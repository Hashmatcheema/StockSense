import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/scenario.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'live_run_screen.dart';

class ScenariosScreen extends StatefulWidget {
  const ScenariosScreen({super.key});

  @override
  State<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _loadError;

  List<dynamic> _latestRuns = [];
  List<Scenario> _scenarios = [];
  Map<String, dynamic>? _monitorConfig;
  Timer? _refreshTimer;

  late AnimationController _pulseCtrl;

  // Fallback scenario data when backend is unreachable
  final List<Map<String, dynamic>> _fallbackScenarios = [
    {
      'id': 'S1',
      'title': 'Supply Chain Disruption — Happy Path',
      'description': 'Karachi Cool Imports has gone silent.',
      'source_count': 6,
      'tags': ['happy-path', 'stockout', 'supply-chain'],
    },
    {
      'id': 'S2',
      'title': 'Conflicting Market Intelligence',
      'description': 'Three sources report wildly different stock levels.',
      'source_count': 5,
      'tags': ['contradictions', 'credibility', 'filtering'],
    },
    {
      'id': 'S3',
      'title': 'Order Failure & Automated Recovery',
      'description': 'A critical reorder action fails.',
      'source_count': 5,
      'tags': ['failure', 'recovery', 'rollback'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fetchData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchDataSilently());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final runs = await _api.getLatestRuns(20);
      final config = await _api.getMonitorConfig();
      // Try to load scenarios from backend
      _scenarios = _fallbackScenarios.map((s) => Scenario.fromJson(s)).toList();
      if (mounted) {
        setState(() {
          _latestRuns = runs ?? [];
          _monitorConfig = config;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      // Use fallback scenarios even on error
      _scenarios = _fallbackScenarios.map((s) => Scenario.fromJson(s)).toList();
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDataSilently() async {
    try {
      final runs = await _api.getLatestRuns(20);
      final config = await _api.getMonitorConfig();
      if (_scenarios.isEmpty) {
        _scenarios = _fallbackScenarios.map((s) => Scenario.fromJson(s)).toList();
      }
      if (mounted) {
        setState(() {
          if (runs != null) _latestRuns = runs;
          if (config != null) _monitorConfig = config;
          if (_isLoading) _isLoading = false;
          _loadError = null;
        });
      }
    } catch (_) {}
  }

  String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    return "${diff.inHours}h ago";
  }

  @override
  Widget build(BuildContext context) {
    final autonomousRuns = _latestRuns.where((r) => r['trigger_type'] == 'autonomous').toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.actionPrimary, size: 22),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('StockSense',
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                Text('Khan Traders · Lahore',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 20),
            onPressed: () => Navigator.pushNamed(context, '/settings').then((_) => _fetchData()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildMonitoringStatusBar(),
                  if (_loadError != null) _buildErrorBanner(),
                  if (autonomousRuns.isNotEmpty) _buildActiveAlerts(autonomousRuns),
                  const SizedBox(height: 16),
                  _buildManualScenarios(),
                  if (_latestRuns.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildRecentRuns(),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tintCritical,
        border: const Border(left: BorderSide(width: 4, color: AppColors.stateCritical)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.stateCritical, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Backend not reachable',
                style: GoogleFonts.inter(color: AppColors.stateCritical, fontSize: 12)),
          ),
          TextButton(
            onPressed: _fetchData,
            child: Text('Retry', style: GoogleFonts.inter(color: AppColors.stateCritical, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringStatusBar() {
    final nextCheck = _monitorConfig?['next_run_in_seconds'] ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) => Opacity(
                  opacity: 0.3 + (_pulseCtrl.value * 0.7),
                  child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppColors.stateOk, shape: BoxShape.circle)),
                ),
              ),
              const SizedBox(width: 6),
              Text('Monitoring · next check in ${nextCheck}s',
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveAlerts(List<dynamic> alerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: AppColors.stateCritical, size: 14),
              const SizedBox(width: 6),
              Text('Active Alerts',
                  style: GoogleFonts.inter(
                      color: AppColors.stateCritical, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${alerts.length} alert${alerts.length > 1 ? 's' : ''}',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        ...alerts.map((run) {
          final s = _scenarios.firstWhere(
              (x) => x.id == run['scenario_id'],
              orElse: () => Scenario(id: run['scenario_id'] ?? '??', title: 'Unknown', description: '', sourceCount: 0));
          final dt = DateTime.parse(run['started_at'] ?? DateTime.now().toIso8601String());
          final isComplete = run['phase'] == 'completed';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.tintCritical,
              borderRadius: BorderRadius.circular(6),
              border: const Border(left: BorderSide(width: 4, color: AppColors.stateCritical)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.stateCritical, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('${run['scenario_id']}  ·  ${s.title}',
                                style: GoogleFonts.inter(
                                    color: AppColors.stateCritical,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(run['trigger_reason'] ?? 'Threshold breached',
                          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusPill(
                            label: isComplete ? 'Completed' : 'Running',
                            color: isComplete ? AppColors.stateOk : AppColors.stateWarn,
                            tint: isComplete ? AppColors.tintOk : AppColors.tintWarn,
                          ),
                          const Spacer(),
                          Text(timeAgo(dt),
                              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openRun(run['run_id'], run['scenario_id']),
                  child: Text('View →',
                      style: GoogleFonts.inter(
                          color: AppColors.stateCritical, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildManualScenarios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('Scenarios',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: _scenarios.asMap().entries.map((e) {
              final idx = e.key;
              final s = e.value;
              return Column(
                children: [
                  InkWell(
                    onTap: () => _startManualScenario(s),
                    borderRadius: idx == 0
                        ? const BorderRadius.vertical(top: Radius.circular(8))
                        : idx == _scenarios.length - 1
                            ? const BorderRadius.vertical(bottom: Radius.circular(8))
                            : BorderRadius.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(AppColors.scenarioIcon(s.id),
                              color: AppColors.actionPrimary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: AppColors.surface2,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: AppColors.border)),
                                      child: Text(s.id,
                                          style: GoogleFonts.inter(
                                              color: AppColors.textSecondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(s.title,
                                          style: GoogleFonts.inter(
                                              color: AppColors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          border: Border.all(color: AppColors.border),
                                          borderRadius: BorderRadius.circular(20)),
                                      child: Text('${s.sourceCount} sources',
                                          style: GoogleFonts.inter(
                                              color: AppColors.textMuted, fontSize: 10)),
                                    ),
                                    ...s.tags.map((t) => Container(
                                          padding:
                                              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                              border: Border.all(color: AppColors.border),
                                              borderRadius: BorderRadius.circular(20)),
                                          child: Text(t,
                                              style: GoogleFonts.inter(
                                                  color: AppColors.textMuted, fontSize: 10)),
                                        )),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.play_arrow_rounded,
                              color: AppColors.actionPrimary, size: 20),
                        ],
                      ),
                    ),
                  ),
                  if (idx < _scenarios.length - 1)
                    const Divider(height: 1, color: AppColors.border),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentRuns() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('Recent Runs',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: _latestRuns.map((r) {
              final isAuto = r['trigger_type'] == 'autonomous';
              final isComplete = r['phase'] == 'completed';
              final dt = DateTime.parse(r['started_at'] ?? DateTime.now().toIso8601String());

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        // Scenario ID + trigger chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.surface2,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(3)),
                          child: Text(r['scenario_id'] ?? '',
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        if (isAuto)
                          StatusPill(
                              label: 'auto',
                              color: AppColors.stateCritical,
                              tint: AppColors.tintCritical),
                        const SizedBox(width: 8),
                        // Phase
                        StatusPill(
                          label: isComplete ? 'Completed' : 'Running',
                          color: isComplete ? AppColors.stateOk : AppColors.stateWarn,
                          tint: isComplete ? AppColors.tintOk : AppColors.tintWarn,
                        ),
                        const Spacer(),
                        Text(timeAgo(dt),
                            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (r != _latestRuns.last) const Divider(height: 1, color: AppColors.border),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _startManualScenario(Scenario scenario) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary)),
    );

    final runId = await _api.startRun(scenario.id);
    if (mounted) Navigator.of(context).pop();

    if (runId != null) {
      _openRun(runId, scenario.id);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start scenario'), backgroundColor: AppColors.stateCritical));
    }
  }

  void _openRun(String runId, String scenarioId) {
    final scenario = _scenarios.firstWhere((s) => s.id == scenarioId,
        orElse: () => Scenario(id: scenarioId, title: 'Scenario $scenarioId', description: '', sourceCount: 0));
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => LiveRunScreen(runId: runId, scenario: scenario),
        ))
        .then((_) => _fetchData());
  }
}
