import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Global error reporter. Routes API/network failures into:
///   1. debugPrint (developer console)
///   2. a transient SnackBar via [scaffoldMessengerKey] (visible to user)
///
/// Replaces the previous silent `catch (_) {}` swallow scattered across the
/// codebase. Add new error categories here, not inline.
class ErrorBus {
  /// Wired into [MaterialApp.scaffoldMessengerKey] so we can surface toasts
  /// from anywhere — even outside the widget tree (e.g. background polling).
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// `silent: true` for background-poll style errors (logged, not toasted).
  static void report(Object error, {String? context, bool silent = false}) {
    final tag = context == null ? '' : '[$context] ';
    debugPrint('ErrorBus: $tag$error');
    if (silent) return;
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.stateCritical,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text(
          context == null ? error.toString() : '$context: $error',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
