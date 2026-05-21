import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/scenario.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../models/state_diff.dart';
import 'before_after_screen.dart';
import 'live_run_screen.dart';

const _kCachedRunsKey = 'cached_latest_runs_v1';
const _kCachedMonitorKey = 'cached_monitor_config_v1';

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
  bool _offlineMode = false;
  bool _fetchInFlight = false;

  StateDiff? _latestDiff;
  String? _latestDiffRunId;
  String? _latestDiffScenarioId;

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
    _bootstrap();
    _refreshTimer = Timer.periodic(Duration(seconds: ApiConfig.pollIntervalSeconds), (_) => _fetchData(silent: true));
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final offline = prefs.getBool('offline_mode') ?? false;
    // Hydrate from cache immediately so the screen is never blank.
    final cachedRunsRaw = prefs.getString(_kCachedRunsKey);
    final cachedMonitorRaw = prefs.getString(_kCachedMonitorKey);
    List<dynamic> cachedRuns = const [];
    Map<String, dynamic>? cachedMonitor;
    try {
      if (cachedRunsRaw != null) cachedRuns = jsonDecode(cachedRunsRaw) as List<dynamic>;
    } catch (_) {}
    try {
      if (cachedMonitorRaw != null) cachedMonitor = jsonDecode(cachedMonitorRaw) as Map<String, dynamic>;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _offlineMode = offline;
        _latestRuns = cachedRuns;
        _monitorConfig = cachedMonitor;
        _scenarios = _fallbackScenarios.map((s) => Scenario.fromJson(s)).toList();
        _isLoading = false; // cache or fallback is already enough to render
      });
    }
    // In offline mode skip the network fetch entirely.
    if (!offline) _fetchData();
  }

  Future<void> _setOfflineMode(bool value) async {
    setState(() => _offlineMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_mode', value);
    if (!value) _fetchData(silent: false); // re-sync immediately when going back online
  }

  Future<void> _persistCache(List<dynamic>? runs, Map<String, dynamic>? config) async {
    final prefs = await SharedPreferences.getInstance();
    if (runs != null) await prefs.setString(_kCachedRunsKey, jsonEncode(runs));
    if (config != null) await prefs.setString(_kCachedMonitorKey, jsonEncode(config));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (_offlineMode || _fetchInFlight) return;
    _fetchInFlight = true;
    try {
      final runs = await _api.getLatestRuns(20);
      final config = await _api.getMonitorConfig();
      if (!silent && _scenarios.isEmpty) {
        _scenarios = _fallbackScenarios.map((s) => Scenario.fromJson(s)).toList();
      }
      final ok = runs != null || config != null;
      if (ok) _persistCache(runs, config);

      // #16: In silent mode, skip setState entirely when nothing meaningful changed.
      if (silent && runs != null && config != null) {
        final runsUnchanged = runs.length == _latestRuns.length &&
            (runs.isEmpty ||
                runs[0]['run_id'] == (_latestRuns.isNotEmpty ? _latestRuns[0]['run_id'] : '') &&
                runs[0]['phase'] == (_latestRuns.isNotEmpty ? _latestRuns[0]['phase'] : ''));
        final configUnchanged = _monitorConfig != null &&
            config['interval_seconds'] == _monitorConfig!['interval_seconds'] &&
            config['next_run_in_seconds'] == _monitorConfig!['next_run_in_seconds'];
        if (runsUnchanged && configUnchanged) return;
      }

      if (mounted) {
        setState(() {
          if (runs != null) _latestRuns = runs;
          if (config != null) {
            _monitorConfig = config;
            ApiConfig.updateFromMonitorConfig(config);
          }
          _isLoading = false;
          if (!silent || ok) _loadError = ok ? null : 'Backend not reachable';
        });
        _refreshLatestDiff();
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
      }
      // Silent mode swallows transient errors during background polling.
    } finally {
      _fetchInFlight = false;
    }
  }

  /// Pull the most recent completed run's state diff so the home screen can
  /// surface a one-glance impact card without making the user dig.
  Future<void> _refreshLatestDiff() async {
    final latestCompleted = _latestRuns.firstWhere(
      (r) => r['phase'] == 'completed',
      orElse: () => null,
    );
    if (latestCompleted == null) return;
    final runId = latestCompleted['run_id'] as String?;
    if (runId == null || runId == _latestDiffRunId) return;
    final diff = await _api.getStateDiff(runId);
    if (!mounted || diff == null) return;
    setState(() {
      _latestDiff = diff;
      _latestDiffRunId = runId;
      _latestDiffScenarioId = latestCompleted['scenario_id'] as String?;
    });
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
        backgroundColor: AppColors.surface,
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
                Text(ApiConfig.companyName,
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          // Connection-state dot — green when last fetch succeeded, red on
          // failure. Silent so it doesn't replace the LIVE/OFFLINE pill;
          // it complements it with a fresher signal.
          Tooltip(
            message: _loadError != null
                ? 'Backend unreachable'
                : (_offlineMode ? 'Offline (using cached data)' : 'Connected'),
            child: Container(
              margin: const EdgeInsets.only(right: 8, left: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _loadError != null
                    ? AppColors.stateCritical
                    : (_offlineMode ? AppColors.stateWarn : AppColors.stateOk),
              ),
            ),
          ),
          Tooltip(
            message: _offlineMode ? 'Offline mode (cached)' : 'Live mode',
            child: GestureDetector(
              onTap: () => _setOfflineMode(!_offlineMode),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _offlineMode ? AppColors.tintWarn : Colors.transparent,
                  border: Border.all(
                    color: _offlineMode ? AppColors.stateWarn : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _offlineMode ? 'OFFLINE' : 'LIVE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _offlineMode ? AppColors.stateWarn : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 20),
            onPressed: () => Navigator.pushNamed(context, '/settings').then((_) => _fetchData()),
          ),
        ],
      ),
      body: _isLoading
          ? const _ScenariosSkeleton()
          : RefreshIndicator(
              onRefresh: _fetchData,
              color: AppColors.actionPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildMonitoringStatusBar(),
                    if (_loadError != null) _buildErrorBanner(),
                    if (autonomousRuns.isNotEmpty) _buildActiveAlerts(autonomousRuns),
                    if (_latestDiff != null) _buildLatestImpactCard(),
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
    // Deduplicate: keep only the most recent run per scenario.
    // The list comes in newest-first order so putIfAbsent keeps the latest.
    final Map<String, dynamic> latestByScenario = {};
    final Map<String, int> countByScenario = {};
    for (final run in alerts) {
      final sid = run['scenario_id'] as String? ?? '?';
      countByScenario[sid] = (countByScenario[sid] ?? 0) + 1;
      latestByScenario.putIfAbsent(sid, () => run);
    }
    final deduped = latestByScenario.values.toList();

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
              Text('${alerts.length} trigger${alerts.length > 1 ? 's' : ''} · ${deduped.length} scenario${deduped.length > 1 ? 's' : ''}',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        ...deduped.map((run) {
          final sid = run['scenario_id'] as String? ?? '?';
          final triggerCount = countByScenario[sid] ?? 1;
          final s = _scenarios.firstWhere(
              (x) => x.id == sid,
              orElse: () => Scenario(id: sid, title: 'Unknown', description: '', sourceCount: 0));
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
                            child: Text('$sid  ·  ${s.title}',
                                style: GoogleFonts.inter(
                                    color: AppColors.stateCritical,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ),
                          if (triggerCount > 1) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.stateCritical,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('×$triggerCount',
                                  style: GoogleFonts.inter(
                                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(run['trigger_reason'] ?? 'Threshold breached',
                          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                      const SizedBox(height: 6),
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

  Widget _buildLatestImpactCard() {
    final d = _latestDiff!;
    final scenarioId = _latestDiffScenarioId ?? '?';
    final runId = _latestDiffRunId;
    final scenario = _scenarios.firstWhere(
      (s) => s.id == scenarioId,
      orElse: () => Scenario(id: scenarioId, title: 'Latest analysis', description: '', sourceCount: 0),
    );

    final bRisk = d.before.riskMetrics.stockoutRiskPct;
    final aRisk = d.after.riskMetrics.stockoutRiskPct;
    final riskDelta = bRisk - aRisk;

    final bRev = d.before.riskMetrics.revenueAtRiskPkr;
    final aRev = d.after.riskMetrics.revenueAtRiskPkr;
    final revSaved = bRev - aRev;

    final improved = riskDelta > 0 || revSaved > 0;
    final accent = improved ? AppColors.stateOk : AppColors.stateWarn;
    final tint = improved ? AppColors.tintOk : AppColors.tintWarn;

    String fmt(num v) {
      if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
      return v.toStringAsFixed(0);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: runId == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BeforeAfterScreen(runId: runId, scenario: scenario),
                ));
              },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_outlined, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Text('Latest Impact',
                      style: GoogleFonts.inter(
                          color: accent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  const Spacer(),
                  Text('Tap to view full report →',
                      style: GoogleFonts.inter(
                          color: accent, fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 10),
              Text(scenario.title,
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _impactStat(
                      label: 'Stockout risk',
                      before: '${bRisk.toStringAsFixed(0)}%',
                      after: '${aRisk.toStringAsFixed(0)}%',
                      delta: riskDelta > 0
                          ? '↓ ${riskDelta.toStringAsFixed(0)} pts'
                          : (riskDelta < 0 ? '↑ ${riskDelta.abs().toStringAsFixed(0)} pts' : '—'),
                      good: riskDelta > 0,
                    ),
                  ),
                  Container(width: 1, height: 36, color: accent.withValues(alpha: 0.2)),
                  Expanded(
                    child: _impactStat(
                      label: 'Revenue at risk',
                      before: 'Rs ${fmt(bRev)}',
                      after: 'Rs ${fmt(aRev)}',
                      delta: revSaved > 0
                          ? '↓ Rs ${fmt(revSaved)}'
                          : (revSaved < 0 ? '↑ Rs ${fmt(revSaved.abs())}' : '—'),
                      good: revSaved > 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _impactStat({
    required String label,
    required String before,
    required String after,
    required String delta,
    required bool good,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(before,
                  style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(after,
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(delta,
              style: GoogleFonts.inter(
                  color: good ? AppColors.stateOk : AppColors.stateCritical,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
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
                  Semantics(
                    button: true,
                    label: 'Run scenario ${s.id}: ${s.title}',
                    child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _startManualScenario(s);
                    },
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

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildRunTile(dynamic r, {BorderRadius? borderRadius}) {
    final isAuto = r['trigger_type'] == 'autonomous';
    final isComplete = r['phase'] == 'completed';
    final dt = DateTime.parse(r['started_at'] ?? DateTime.now().toIso8601String());
    final runId = r['run_id'] as String?;
    final scenarioId = r['scenario_id'] as String?;
    final scenario = _scenarios.firstWhere(
        (s) => s.id == scenarioId,
        orElse: () => Scenario(id: scenarioId ?? '?', title: '', description: '', sourceCount: 0));

    return InkWell(
      onTap: runId != null && scenarioId != null
          ? () {
              HapticFeedback.selectionClick();
              _openRun(runId, scenarioId);
            }
          : null,
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(3)),
              child: Text(scenarioId ?? '',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(scenario.title,
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            const SizedBox(width: 8),
            if (isAuto)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: StatusPill(
                    label: 'auto',
                    color: AppColors.stateCritical,
                    tint: AppColors.tintCritical),
              ),
            StatusPill(
              label: isComplete ? 'Done' : 'Running',
              color: isComplete ? AppColors.stateOk : AppColors.stateWarn,
              tint: isComplete ? AppColors.tintOk : AppColors.tintWarn,
            ),
            const SizedBox(width: 8),
            Text(timeAgo(dt),
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        final List<MapEntry<String, List<dynamic>>> dayGroups = [];
        final Map<String, List<dynamic>> seen = {};
        for (final r in _latestRuns) {
          final dt = DateTime.parse(r['started_at'] ?? DateTime.now().toIso8601String());
          final label = _dayLabel(dt);
          if (!seen.containsKey(label)) {
            seen[label] = [];
            dayGroups.add(MapEntry(label, seen[label]!));
          }
          seen[label]!.add(r);
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text('Run History',
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Text('${_latestRuns.length} runs',
                        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: dayGroups.map((group) {
                    final dayLabel = group.key;
                    final runs = group.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                          child: Text(dayLabel,
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: runs.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final r = entry.value;
                              BorderRadius? br;
                              if (idx == 0 && runs.length == 1) {
                                br = BorderRadius.circular(8);
                              } else if (idx == 0) {
                                br = const BorderRadius.vertical(top: Radius.circular(8));
                              } else if (idx == runs.length - 1) {
                                br = const BorderRadius.vertical(bottom: Radius.circular(8));
                              }
                              return Column(
                                children: [
                                  _buildRunTile(r, borderRadius: br),
                                  if (idx < runs.length - 1)
                                    const Divider(height: 1, color: AppColors.border),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentRuns() {
    if (_latestRuns.isEmpty) return const SizedBox.shrink();
    final last = _latestRuns.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text('Last Run',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              GestureDetector(
                onTap: _showHistorySheet,
                child: Text('View History →',
                    style: GoogleFonts.inter(
                        color: AppColors.actionPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _buildRunTile(last),
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

    final runId = await _api.startRun(scenario.id, offline: _offlineMode);
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

/// Animated skeleton placeholder shown while the first fetch is in-flight.
/// Replaces the bare CircularProgressIndicator so the page never appears
/// empty / unstructured during cold start.
class _ScenariosSkeleton extends StatefulWidget {
  const _ScenariosSkeleton();
  @override
  State<_ScenariosSkeleton> createState() => _ScenariosSkeletonState();
}

class _ScenariosSkeletonState extends State<_ScenariosSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _box({double? w, double h = 14, double r = 4}) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surface2, AppColors.border, _c.value),
            borderRadius: BorderRadius.circular(r),
          ),
        ),
      );

  Widget _row() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _box(w: 220, h: 14),
            const SizedBox(height: 10),
            _box(w: 140, h: 10),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [_row(), _row(), _row()],
    );
  }
}

