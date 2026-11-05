import 'package:zadachnik_client/features/auth/data/auth_api.dart';
import 'package:zadachnik_client/features/auth/data/auth_models.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';

class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.loginResponse, this.setupResponse, this.refreshResponse});

  AuthResponse? loginResponse;
  AuthResponse? setupResponse;
  AuthResponse? refreshResponse;
  Object? loginError;
  Object? setupError;
  Object? refreshError;
  Object? logoutError;

  int loginCalls = 0;
  int setupCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
    required DeviceInfo device,
  }) async {
    loginCalls += 1;
    if (loginError != null) throw loginError!;
    return loginResponse ?? response();
  }

  @override
  Future<AuthResponse> setup({
    required String setupToken,
    required String email,
    required String password,
    required DeviceInfo device,
  }) async {
    setupCalls += 1;
    if (setupError != null) throw setupError!;
    return setupResponse ?? response();
  }

  @override
  Future<AuthResponse> refresh(String refreshToken) async {
    refreshCalls += 1;
    if (refreshError != null) throw refreshError!;
    return refreshResponse ?? response();
  }

  @override
  Future<void> logout(String refreshToken) async {
    logoutCalls += 1;
    if (logoutError != null) throw logoutError!;
  }

  static AuthResponse response({
    String accessToken = 'access',
    String refreshToken = 'refresh',
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
  }) {
    final now = DateTime.now().toUtc();
    return AuthResponse(
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: accessToken,
      accessExpiresAt: accessExpiresAt ?? now.add(const Duration(minutes: 15)),
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt ?? now.add(const Duration(days: 30)),
    );
  }
}

class NoopSyncController extends SyncController {
  @override
  SyncViewState build() => const SyncViewState.idle();

  @override
  Future<void> sync() async {}
}
