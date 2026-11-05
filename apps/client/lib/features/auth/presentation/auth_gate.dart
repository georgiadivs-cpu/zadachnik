import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/home_shell.dart';
import '../application/auth_controller.dart';
import 'login_page.dart';
import 'splash_page.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return switch (auth.status) {
      AuthStatus.loading => const SplashPage(),
      AuthStatus.unauthenticated => const LoginPage(),
      AuthStatus.authenticated => const HomeShell(),
    };
  }
}
