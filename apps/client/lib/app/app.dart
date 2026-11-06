import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_gate.dart';
import '../features/backup/presentation/backup_status_bar.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ZadachnikApp extends StatelessWidget {
  const ZadachnikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D5B),
      brightness: Brightness.light,
    );

    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
      builder: (context, child) =>
          BackupStatusHost(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}
