import 'package:flutter/material.dart';
import '../models/scenario.dart';
import '../services/api_service.dart';
import 'live_run_screen.dart';

/// Scenarios screen — lists the three acceptance scenarios (FR-6.1).
class ScenariosScreen extends StatefulWidget {
  const ScenariosScreen({super.key});

  @override
  State<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final List<Map<String, dynamic>> _scenarios = [
    {
      'id': 'S1',
      'title': 'Supply Chain Disruption — Happy Path',
      'subtitle': 'Stockout risk, supplier delays, fuel price surge. '
          'System extracts insights, resolves contradictions, generates action plan.',
      'tags': ['5 sources', 'happy-path', 'stockout'],
    },
    {
      'id': 'S2',
      'title': 'Conflicting Market Intelligence',
      'subtitle': 'Three sources report conflicting stock levels. '
          'Low-credibility news source attempts crisis spoofing.',
      'tags': ['5 sources', 'contradictions', 'credibility'],
    },
    {
      'id': 'S3',
      'title': 'Order Failure & Automated Recovery',
      'subtitle': 'Supplier API fails. System retries, attempts substitution, '
          'and rolls back dependent actions.',
      'tags': ['5 sources', 'failure', 'recovery'],
    },
  ];
  final bool _loading = false;
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() { _shimmerCtrl.dispose(); _api.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            Expanded(child: _loading ? _buildLoading() : _buildScenarioList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00BFA6), Color(0xFF00897B)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.insights, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Text('StockSense',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
            ],
          ),
          const SizedBox(height: 16),
          Text('Khan Traders, Lahore',
            style: TextStyle(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 4),
          Text('Select a scenario to run the autonomous agent crew',
            style: TextStyle(fontSize: 16, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator(color: Color(0xFF00BFA6)));
  }

  Widget _buildScenarioList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _scenarios.length,
      itemBuilder: (ctx, i) {
        final data = _scenarios[i];
        final scenario = Scenario(
          id: data['id'] as String,
          title: data['title'] as String,
          description: data['subtitle'] as String,
          sourceCount: 5,
          tags: List<String>.from(data['tags'] as List),
        );
        return _ScenarioTile(
          scenario: scenario,
          index: i,
          onTap: () => _runScenario(scenario),
        );
      },
    );
  }

  Future<void> _runScenario(Scenario scenario) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F38),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Color(0xFF00BFA6)),
            const SizedBox(height: 16),
            Text('Starting ${scenario.id}...',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
      ),
    );

    final runId = await _api.startRun(scenario.id);

    if (mounted) Navigator.of(context).pop(); // dismiss dialog

    if (runId != null && mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LiveRunScreen(runId: runId, scenario: scenario),
      ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start scenario. Is the backend running?',
            style: TextStyle()),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

// ── Scenario Tile ──────────────────────────────────────────────────────────────

class _ScenarioTile extends StatefulWidget {
  final Scenario scenario;
  final int index;
  final VoidCallback onTap;

  const _ScenarioTile({required this.scenario, required this.index, required this.onTap});

  @override
  State<_ScenarioTile> createState() => _ScenarioTileState();
}

class _ScenarioTileState extends State<_ScenarioTile> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  static const _gradients = [
    [Color(0xFF00BFA6), Color(0xFF00897B)],
    [Color(0xFF7C4DFF), Color(0xFF536DFE)],
    [Color(0xFFFF6D00), Color(0xFFFF3D00)],
  ];

  static const _icons = [Icons.local_shipping, Icons.compare_arrows, Icons.autorenew];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[widget.index % _gradients.length];
    final icon = _icons[widget.index % _icons.length];

    return AnimatedBuilder(
      animation: _scale,
      builder: (ctx, child) => Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors[0].withValues(alpha: 0.15), colors[1].withValues(alpha: 0.08)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors[0].withValues(alpha: 0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.scenario.id,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: colors[0])),
                      Text(widget.scenario.title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                          color: Colors.white)),
                    ],
                  ),
                ),
                Icon(Icons.play_circle_fill, color: colors[0], size: 36),
              ]),
              const SizedBox(height: 12),
              Text(widget.scenario.description,
                style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                _chip('${widget.scenario.sourceCount} sources', colors[0]),
                const SizedBox(width: 8),
                ...widget.scenario.tags.take(2).map((t) =>
                  Padding(padding: const EdgeInsets.only(right: 8), child: _chip(t, Colors.white24))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
        style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500)),
    );
  }
}

