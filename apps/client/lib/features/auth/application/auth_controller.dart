import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/auth/session.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/network/api_config.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.session,
    this.error,
    this.offline = false,
  });

  const AuthState.loading() : this(status: AuthStatus.loading);

  const AuthState.unauthenticated({String? error})
    : this(status: AuthStatus.unauthenticated, error: error);

  const AuthState.authenticated(Session session, {bool offline = false})
    : this(
        status: AuthStatus.authenticated,
        session: session,
        offline: offline,
      );

  final AuthStatus status;
  final Session? session;
  final String? error;
  final bool offline;
}

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SecureSessionStore(storage: const FlutterSecureStorage());
});

final authApiProvider = Provider<AuthApi>((ref) {
  return DioAuthApi(baseUrl: apiBaseUrl);
});

final authControllerProvider = NotifierProvider<SessionController, AuthState>(
  SessionController.new,
);

class SessionController extends Notifier<AuthState> {
  bool _bootstrapped = false;

  @override
  AuthState build() => const AuthState.loading();

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;

    final store = ref.read(sessionStoreProvider);
    final session = await store.read();
    if (!ref.mounted) {
      return;
    }
    if (session == null) {
      state = const AuthState.unauthenticated();
      return;
    }
    if (!session.isAccessExpired) {
      state = AuthState.authenticated(session);
      return;
    }

    try {
      final response = await ref
          .read(authApiProvider)
          .refresh(session.refreshToken);
      final refreshed = response.toSession(session.email);
      await store.write(refreshed);
      if (ref.mounted) {
        state = AuthState.authenticated(refreshed);
      }
    } on AuthFailure catch (failure) {
      if (failure.network) {
        if (ref.mounted) {
          state = AuthState.authenticated(session, offline: true);
        }
        return;
      }

      await store.clear();
      if (ref.mounted) {
        state = AuthState.unauthenticated(error: failure.message);
      }
    } on Object {
      if (ref.mounted) {
        state = AuthState.authenticated(session, offline: true);
      }
    }
  }

  /// Возвращает актуальную сессию, обновляя access token при необходимости.
  Future<Session?> ensureFreshSession({bool force = false}) async {
    final current = state.session;
    if (current == null) {
      return null;
    }
    if (!force && !current.isAccessExpired) {
      return current;
    }

    try {
      final response = await ref
          .read(authApiProvider)
          .refresh(current.refreshToken);
      final refreshed = response.toSession(current.email);
      await ref.read(sessionStoreProvider).write(refreshed);
      if (ref.mounted) {
        state = AuthState.authenticated(refreshed);
      }
      return refreshed;
    } on AuthFailure catch (failure) {
      if (failure.network) {
        return current;
      }
      await ref.read(sessionStoreProvider).clear();
      if (ref.mounted) {
        state = AuthState.unauthenticated(error: failure.message);
      }
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final response = await ref
          .read(authApiProvider)
          .login(
            email: email.trim(),
            password: password,
            device: await _device(),
          );
      final session = response.toSession(email);
      await ref.read(sessionStoreProvider).write(session);
      state = AuthState.authenticated(session);
    } on AuthFailure catch (failure) {
      state = AuthState.unauthenticated(error: failure.message);
      rethrow;
    }
  }

  Future<void> setup({
    required String setupToken,
    required String email,
    required String password,
  }) async {
    try {
      final response = await ref
          .read(authApiProvider)
          .setup(
            setupToken: setupToken.trim(),
            email: email.trim(),
            password: password,
            device: await _device(),
          );
      final session = response.toSession(email);
      await ref.read(sessionStoreProvider).write(session);
      state = AuthState.authenticated(session);
    } on AuthFailure catch (failure) {
      state = AuthState.unauthenticated(error: failure.message);
      rethrow;
    }
  }

  Future<void> logout() async {
    final session = state.session;
    if (session != null) {
      try {
        await ref.read(authApiProvider).logout(session.refreshToken);
      } on Object {
        // Локальные данные и выход важнее сетевой ошибки.
      }
    }

    await ref.read(sessionStoreProvider).clear();
    state = const AuthState.unauthenticated();
  }

  Future<DeviceInfo> _device() async {
    final deviceId = await ref
        .read(sessionStoreProvider)
        .readOrCreateDeviceId();
    return DeviceInfo(
      id: deviceId,
      name: _deviceName(),
      platform: _platformName(),
    );
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    if (Platform.isMacOS) return 'MACOS';
    return 'WINDOWS';
  }

  static String _deviceName() {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    return 'Device';
  }
}
