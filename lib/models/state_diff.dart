/// State diff model — mirrors backend StateDiff for Before/After screen.
class StateDiff {
  final BusinessState before;
  final BusinessState after;
  final Map<String, dynamic> changesSummary;

  StateDiff({required this.before, required this.after, required this.changesSummary});

  factory StateDiff.fromJson(Map<String, dynamic> json) => StateDiff(
        before: BusinessState.fromJson(json['before'] ?? {}),
        after: BusinessState.fromJson(json['after'] ?? {}),
        changesSummary: json['changes_summary'] as Map<String, dynamic>? ?? {},
      );
}

class RiskMetrics {
  final double stockoutRiskPct;
  final double revenueAtRiskPkr;

  RiskMetrics({this.stockoutRiskPct = 0, this.revenueAtRiskPkr = 0});

  factory RiskMetrics.fromJson(Map<String, dynamic> json) => RiskMetrics(
        stockoutRiskPct: (json['stockout_risk_pct'] as num?)?.toDouble() ?? 0,
        revenueAtRiskPkr: (json['revenue_at_risk_pkr'] as num?)?.toDouble() ?? 0,
      );
}

class BusinessState {
  final Map<String, int> inventory;
  final Map<String, String> customerEtas;
  final Map<String, String> supplierStatus;
  final List<dynamic> notificationQueue;
  final List<dynamic> openOrders;
  final RiskMetrics riskMetrics;

  BusinessState({
    this.inventory = const {},
    this.customerEtas = const {},
    this.supplierStatus = const {},
    this.notificationQueue = const [],
    this.openOrders = const [],
    RiskMetrics? riskMetrics,
  }) : riskMetrics = riskMetrics ?? RiskMetrics();

  factory BusinessState.fromJson(Map<String, dynamic> json) => BusinessState(
        inventory: (json['inventory'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
        customerEtas: (json['customer_etas'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
        supplierStatus: (json['supplier_status'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
        notificationQueue: json['notification_queue'] as List<dynamic>? ?? [],
        openOrders: json['open_orders'] as List<dynamic>? ?? [],
        riskMetrics: RiskMetrics.fromJson(json['risk_metrics'] as Map<String, dynamic>? ?? {}),
      );
}
