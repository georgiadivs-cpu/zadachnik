import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/auth/session_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('secure storage сохраняет и удаляет сессию', (tester) async {
    final store = SecureSessionStore();
    final deviceId = await store.readOrCreateDeviceId();
    expect(deviceId, isNotEmpty);

    final now = DateTime.now().toUtc();
    final session = Session(
      email: 'device@example.com',
      userId: 'user-1',
      deviceId: deviceId,
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessExpiresAt: now.add(const Duration(minutes: 15)),
      refreshExpiresAt: now.add(const Duration(days: 30)),
    );

    await store.write(session);
    final loaded = await store.read();
    expect(loaded?.accessToken, 'access-token');
    expect(loaded?.deviceId, deviceId);

    await store.clear();
    expect(await store.read(), isNull);
  });
}
