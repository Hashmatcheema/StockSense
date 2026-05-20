import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/api_config.dart';
import 'services/error_bus.dart';
import 'theme/app_theme.dart';
import 'screens/scenarios_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.loadPersistedBase();
  runApp(const StockSenseApp());
}

class StockSenseApp extends StatelessWidget {
  const StockSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockSense',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: ErrorBus.scaffoldMessengerKey,
      builder: (context, child) {
        // Cap text scaling so very large system font sizes don't break layouts.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
          child: child!,
        );
      },
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bg,
        cardColor: AppColors.surface,
        colorScheme: const ColorScheme.light(
          surface: AppColors.surface,
          primary: AppColors.actionPrimary,
          secondary: AppColors.stateInfo,
          error: AppColors.stateCritical,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: AppColors.textSecondary),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.light().textTheme,
        ),
        dividerColor: AppColors.border,
      ),
      home: const ScenariosScreen(),
      routes: {
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
