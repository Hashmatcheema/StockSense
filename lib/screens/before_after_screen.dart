import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/scenario.dart';
import '../models/state_diff.dart';
import '../services/api_service.dart';

/// Before/After screen — shows diffs in business state (FR-6.3).
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
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final diff = await _api.getStateDiff(widget.runId);
    if (mounted) setState(() { _diff = diff; _loading = false; });
  }

  @override
  void dispose() { _api.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1329),
        elevation: 0,
        title: Text('Before / After — ${widget.scenario.id}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFA6)))
          : _diff == null
              ? Center(child: Text('No data available',
                  style: TextStyle(color: Colors.white54)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final d = _diff!;
    final fmt = NumberFormat('#,##0');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk metrics — hero cards
          Text('Risk Overview',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _riskCard(
              'Stockout Risk',
              d.before.riskMetrics.stockoutRiskPct,
              d.after.riskMetrics.stockoutRiskPct,
              '%', isPercentage: true,
            )),
            const SizedBox(width: 12),
            Expanded(child: _riskCard(
              'Revenue at Risk',
              d.before.riskMetrics.revenueAtRiskPkr,
              d.after.riskMetrics.revenueAtRiskPkr,
              'PKR', prefix: '₨ ',
            )),
          ]),

          const SizedBox(height: 28),

          // Inventory changes
          Text('Inventory Changes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ...d.after.inventory.entries.map((e) {
            final before = d.before.inventory[e.key] ?? 0;
            final after = e.value;
            final delta = after - before;
            return _diffRow(e.key, fmt.format(before), fmt.format(after), delta);
          }),

          const SizedBox(height: 28),

          // Supplier status
          Text('Supplier Status',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ...d.after.supplierStatus.entries.map((e) {
            final before = d.before.supplierStatus[e.key] ?? 'unknown';
            return _statusRow(e.key, before, e.value);
          }),

          const SizedBox(height: 28),

          // Notifications and orders
          Text('Actions Taken',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          _infoRow('Notifications sent', '${d.after.notificationQueue.length}'),
          _infoRow('Orders placed', '${d.after.openOrders.length}'),
        ],
      ),
    );
  }

  Widget _riskCard(String label, double before, double after, String unit,
      {bool isPercentage = false, String prefix = ''}) {
    final delta = after - before;
    final improved = delta < 0;
    final fmt = NumberFormat('#,##0.0');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: improved
              ? [const Color(0xFF00BFA6).withValues(alpha: 0.15), const Color(0xFF00897B).withValues(alpha: 0.05)]
              : [Colors.redAccent.withValues(alpha: 0.15), Colors.red.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: improved ? const Color(0xFF00BFA6).withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),
          Text('$prefix${fmt.format(after)}${isPercentage ? unit : ''}',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: improved ? const Color(0xFF00BFA6) : Colors.redAccent)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(improved ? Icons.trending_down : Icons.trending_up,
              size: 16, color: improved ? const Color(0xFF00BFA6) : Colors.redAccent),
            const SizedBox(width: 4),
            Text('${delta > 0 ? '+' : ''}${fmt.format(delta)}${isPercentage ? ' pp' : ''}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: improved ? const Color(0xFF00BFA6) : Colors.redAccent)),
          ]),
          const SizedBox(height: 4),
          Text('Was: $prefix${fmt.format(before)}${isPercentage ? unit : ''}',
            style: TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _diffRow(String sku, String before, String after, int delta) {
    final improved = delta > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141830),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: Text(sku, style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
        ),
        Text(before, style: TextStyle(fontSize: 13, color: Colors.white38)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, size: 14, color: Colors.white24),
        ),
        Text(after, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: improved ? const Color(0xFF00BFA6) : Colors.white)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: improved
                ? const Color(0xFF00BFA6).withValues(alpha: 0.15)
                : Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${delta > 0 ? '+' : ''}$delta',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: improved ? const Color(0xFF00BFA6) : Colors.redAccent),
          ),
        ),
      ]),
    );
  }

  Widget _statusRow(String supplier, String before, String after) {
    final changed = before != after;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141830),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(child: Text(supplier,
          style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500))),
        Text(before, style: TextStyle(fontSize: 12, color: Colors.white38)),
        if (changed) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 14, color: Colors.white24),
          ),
          Text(after, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: after == 'active' ? const Color(0xFF00BFA6) : Colors.amber)),
        ],
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141830),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(child: Text(label,
          style: TextStyle(fontSize: 13, color: Colors.white70))),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
          color: const Color(0xFF00BFA6))),
      ]),
    );
  }
}
