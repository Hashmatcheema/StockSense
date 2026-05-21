import 'package:flutter/material.dart';

/// Design tokens for StockSense — semantic color system for supply-chain ops.
/// All colors carry meaning (healthy / at-risk / failed), never used decoratively.
class AppColors {
  // Canvas — light theme
  static const bg = Color(0xFFF8F9FA);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1F3F5);
  static const border = Color(0xFFDEE2E6);
  static const borderStrong = Color(0xFFADB5BD);

  // Text
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF374151);
  static const textMuted = Color(0xFF6B7280);

  // SEMANTIC — these carry meaning, never used decoratively
  static const stateOk = Color(0xFF059669);
  static const stateWarn = Color(0xFFD97706);
  static const stateCritical = Color(0xFFDC2626);
  static const stateInfo = Color(0xFF2563EB);

  // Action-only — never on text
  static const actionPrimary = Color(0xFF059669);
  static const actionPrimaryHover = Color(0xFF047857);

  // Tints for backgrounds (cards/banners) — light variants
  static const tintOk = Color(0xFFD1FAE5);
  static const tintWarn = Color(0xFFFEF3C7);
  static const tintCritical = Color(0xFFFEE2E2);
  static const tintInfo = Color(0xFFDBEAFE);

  /// Semantic color for trace event left border based on event_type.
  static Color eventColor(String eventType) {
    switch (eventType) {
      case 'agent_end':
      case 'source_accepted':
        return stateOk;
      case 'action_executed':
        return stateOk;
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

  /// Human-readable label for each agent — surfaces to non-technical users.
  static String agentLabel(String agentName) {
    switch (agentName) {
      case 'ingestion':
        return 'Source Reader';
      case 'insight':
        return 'Risk Analyst';
      case 'planner':
        return 'Action Planner';
      case 'executor':
        return 'Action Taker';
      case 'supervisor':
        return 'Coordinator';
      default:
        return agentName;
    }
  }

  /// Human-readable label for each event_type.
  static String eventLabel(String eventType) {
    switch (eventType) {
      case 'agent_start':
        return 'Started';
      case 'agent_end':
        return 'Completed';
      case 'source_accepted':
        return 'Source accepted';
      case 'filtered_out':
        return 'Source filtered out';
      case 'conflict_resolved':
        return 'Conflict resolved';
      case 'action_executed':
        return 'Action taken';
      case 'action_failed':
        return 'Action failed';
      case 'action_retried':
        return 'Retrying action';
      case 'plan_generated':
        return 'Plan ready';
      case 'agent_failed':
        return 'Agent error';
      case 'extraction_error':
        return 'Extraction issue';
      default:
        return eventType.replaceAll('_', ' ');
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
    // Darken the label one step beyond the border colour when sitting on a
    // tinted background — fixes WCAG-AA contrast failures we saw on the
    // light tint variants (tintOk/tintWarn/tintCritical).
    final hsl = HSLColor.fromColor(color);
    final textColor = tint == null
        ? color
        : hsl.withLightness((hsl.lightness * 0.7).clamp(0.0, 1.0)).toColor();

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: tint,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
