import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/api_config.dart';
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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        cardColor: AppColors.surface,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.surface,
          primary: AppColors.actionPrimary,
          secondary: AppColors.stateInfo,
          error: AppColors.stateCritical,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
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
          ThemeData.dark().textTheme,
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
