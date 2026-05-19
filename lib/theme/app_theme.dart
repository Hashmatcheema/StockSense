import 'package:flutter/material.dart';

/// Design tokens for StockSense — semantic color system for supply-chain ops.
/// All colors carry meaning (healthy / at-risk / failed), never used decoratively.
class AppColors {
  // Canvas — dark theme
  static const bg = Color(0xFF0A0E1A);
  static const surface = Color(0xFF111827);
  static const surface2 = Color(0xFF1F2937);
  static const border = Color(0xFF374151);
  static const borderStrong = Color(0xFF4B5563);

  // Text
  static const textPrimary = Color(0xFFF9FAFB);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);

  // SEMANTIC — these carry meaning, never used decoratively
  static const stateOk = Color(0xFF10B981);
  static const stateWarn = Color(0xFFF59E0B);
  static const stateCritical = Color(0xFFEF4444);
  static const stateInfo = Color(0xFF3B82F6);

  // Action-only — never on text
  static const actionPrimary = Color(0xFF10B981);
  static const actionPrimaryHover = Color(0xFF059669);

  // Tints for backgrounds (cards/banners) — dark variants
  static const tintOk = Color(0xFF052E16);
  static const tintWarn = Color(0xFF451A03);
  static const tintCritical = Color(0xFF450A0A);
  static const tintInfo = Color(0xFF1E3A8A);

  /// Semantic color for trace event left border based on event_type.
  static Color eventColor(String eventType) {
    switch (eventType) {
      case 'agent_end':
      case 'source_accepted':
        return stateOk;
      case 'action_executed':
        return stateOk; // Could check status detail for failures
      case 'filtered_out':
      case 'action_retried':
      case 'conflict_resolved':
        return stateWarn;
      case 'action_failed':
      case 'extraction_error':
      case 'agent_failed':
        return stateCritical;
      default:
        return border;
    }
  }

  /// Icon for each agent type.
  static IconData agentIcon(String agentName) {
    switch (agentName) {
      case 'ingestion':
        return Icons.description_outlined;
      case 'insight':
        return Icons.search_outlined;
      case 'planner':
        return Icons.account_tree_outlined;
      case 'executor':
        return Icons.bolt_outlined;
      case 'supervisor':
        return Icons.hub_outlined;
      default:
        return Icons.smart_toy_outlined;
    }
  }

  /// Semantic color for stockout risk percentage.
  static Color riskColor(double pct) {
    if (pct >= 60) return stateCritical;
    if (pct >= 30) return stateWarn;
    return stateOk;
  }

  /// Supplier status colors.
  static Color supplierColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return stateOk;
      case 'delayed':
        return stateWarn;
      case 'silent':
        return stateCritical;
      default:
        return textMuted;
    }
  }

  /// Supplier status tint.
  static Color supplierTint(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return tintOk;
      case 'delayed':
        return tintWarn;
      case 'silent':
        return tintCritical;
      default:
        return surface2;
    }
  }

  /// Scenario type icon.
  static IconData scenarioIcon(String scenarioId) {
    switch (scenarioId) {
      case 'S1':
        return Icons.local_shipping_outlined;
      case 'S2':
        return Icons.compare_arrows_outlined;
      case 'S3':
        return Icons.replay_outlined;
      default:
        return Icons.science_outlined;
    }
  }
}

/// Reusable status pill widget.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color? tint;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}
