import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/auth/session_store.dart';
import 'package:zadachnik_client/features/auth/application/auth_controller.dart';
import 'package:zadachnik_client/features/auth/data/auth_api.dart';

import 'fakes.dart';

void main() {
  late InMemorySessionStore store;
  late FakeAuthApi api;
  late ProviderContainer container;

  setUp(() {
    store = InMemorySessionStore(deviceId: 'device-1');
    api = FakeAuthApi();
    container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(api),
      ],
    );
  });

  tearDown(() => container.dispose());

  SessionController controller() =>
      container.read(authControllerProvider.notifier);

  AuthState state() => container.read(authControllerProvider);

  test('bootstrap without session returns unauthenticated', () async {
    await controller().bootstrap();

    expect(state().status, AuthStatus.unauthenticated);
    expect(api.refreshCalls, 0);
  });

  test('login stores session and authenticates', () async {
    await controller().bootstrap();
    await controller().login(email: 'Owner@Example.com', password: 'password-1234');

    expect(state().status, AuthStatus.authenticated);
    expect(state().session?.email, 'owner@example.com');
    expect(api.loginCalls, 1);
    expect((await store.read())?.accessToken, 'access');
  });

  test('bootstrap refreshes expired access token', () async {
    final now = DateTime.now().toUtc();
    store.session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      accessExpiresAt: now.subtract(const Duration(minutes: 1)),
      refreshExpiresAt: now.add(const Duration(days: 1)),
    );
    api.refreshResponse = FakeAuthApi.response(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );

    await controller().bootstrap();

    expect(state().status, AuthStatus.authenticated);
    expect(state().session?.accessToken, 'new-access');
    expect(api.refreshCalls, 1);
    expect((await store.read())?.refreshToken, 'new-refresh');
  });

  test('bootstrap keeps local access when server is unavailable', () async {
    final now = DateTime.now().toUtc();
    store.session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      accessExpiresAt: now.subtract(const Duration(minutes: 1)),
      refreshExpiresAt: now.add(const Duration(days: 1)),
    );
    api.refreshError = const AuthFailure(
      code: 'NETWORK_ERROR',
      message: 'Сервер недоступен',
      network: true,
    );

    await controller().bootstrap();

    expect(state().status, AuthStatus.authenticated);
    expect(state().offline, isTrue);
    expect((await store.read())?.accessToken, 'old-access');
  });

  test('bootstrap clears invalid refresh session', () async {
    final now = DateTime.now().toUtc();
    store.session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      accessExpiresAt: now.subtract(const Duration(minutes: 1)),
      refreshExpiresAt: now.add(const Duration(days: 1)),
    );
    api.refreshError = const AuthFailure(
      code: 'REFRESH_TOKEN_INVALID',
      message: 'Сессия недействительна',
    );

    await controller().bootstrap();

    expect(state().status, AuthStatus.unauthenticated);
    expect(await store.read(), isNull);
  });

  test('logout clears session even when server is unavailable', () async {
    await controller().bootstrap();
    await controller().login(email: 'owner@example.com', password: 'password-1234');
    api.logoutError = const AuthFailure(
      code: 'NETWORK_ERROR',
      message: 'Сервер недоступен',
      network: true,
    );

    await controller().logout();

    expect(state().status, AuthStatus.unauthenticated);
    expect(await store.read(), isNull);
  });

  test('login failure exposes message and stays unauthenticated', () async {
    api.loginError = const AuthFailure(
      code: 'INVALID_CREDENTIALS',
      message: 'Неверный email или пароль',
    );

    await expectLater(
      controller().login(email: 'owner@example.com', password: 'wrong-password'),
      throwsA(isA<AuthFailure>()),
    );

    expect(state().status, AuthStatus.unauthenticated);
    expect(state().error, 'Неверный email или пароль');
  });
}
