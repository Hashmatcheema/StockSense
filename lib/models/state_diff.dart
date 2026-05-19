/// State diff model — mirrors backend StateDiff for Before/After screen.
class StateDiff {
  final BusinessState before;
  final BusinessState after;
  final Map<String, dynamic> changesSummary;
  final List<TakenAction> actionsTaken;
  final Map<String, dynamic>? actionPlan;

  StateDiff({
    required this.before,
    required this.after,
    required this.changesSummary,
    this.actionsTaken = const [],
    this.actionPlan,
  });

  factory StateDiff.fromJson(Map<String, dynamic> json) => StateDiff(
        before: BusinessState.fromJson(json['before'] ?? {}),
        after: BusinessState.fromJson(json['after'] ?? {}),
        changesSummary: json['changes_summary'] as Map<String, dynamic>? ?? {},
        actionsTaken: (json['actions_taken'] as List<dynamic>?)
                ?.map((a) => TakenAction.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        actionPlan: json['action_plan'] as Map<String, dynamic>?,
      );
}

class TakenAction {
  final String kind;
  final String rationale;

  TakenAction({required this.kind, required this.rationale});

  factory TakenAction.fromJson(Map<String, dynamic> json) => TakenAction(
        kind: json['kind'] as String? ?? 'unknown',
        rationale: json['rationale'] as String? ?? '',
      );
}

class RiskMetrics {
  final double stockoutRiskPct;
  final double revenueAtRiskPkr;
  final int daysOfStockRemaining;
  final int pendingCustomerOrdersAffected;

  RiskMetrics({
    this.stockoutRiskPct = 0,
    this.revenueAtRiskPkr = 0,
    this.daysOfStockRemaining = 0,
    this.pendingCustomerOrdersAffected = 0,
  });

  factory RiskMetrics.fromJson(Map<String, dynamic> json) => RiskMetrics(
        stockoutRiskPct: (json['stockout_risk_pct'] as num?)?.toDouble() ?? 0,
        revenueAtRiskPkr: (json['revenue_at_risk_pkr'] as num?)?.toDouble() ?? 0,
        daysOfStockRemaining: (json['days_of_stock_remaining'] as num?)?.toInt() ?? 0,
        pendingCustomerOrdersAffected: (json['pending_customer_orders_affected'] as num?)?.toInt() ?? 0,
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
