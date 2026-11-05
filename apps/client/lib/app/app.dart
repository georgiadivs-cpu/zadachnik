import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_gate.dart';

class ZadachnikApp extends StatelessWidget {
  const ZadachnikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D5B),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Ежедневник',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4FAF5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFDCEFDF),
          foregroundColor: Color(0xFF1E2B21),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
