import 'package:flutter/material.dart';
import 'screens/scenarios_screen.dart';

void main() {
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
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        primaryColor: const Color(0xFF00BFA6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BFA6),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF141830),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF0F1329),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        textTheme: ThemeData.dark().textTheme,
      ),
      home: const ScenariosScreen(),
    );
  }
}
