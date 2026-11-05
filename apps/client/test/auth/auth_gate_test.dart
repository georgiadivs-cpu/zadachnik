import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/app/app.dart';
import 'package:zadachnik_client/core/auth/session_store.dart';
import 'package:zadachnik_client/features/auth/application/auth_controller.dart';
import 'package:zadachnik_client/features/auth/data/auth_models.dart';
import 'package:zadachnik_client/features/notes/application/notes_providers.dart';
import 'package:zadachnik_client/features/notes/domain/note.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';

import 'fakes.dart';

void main() {
  testWidgets('вход открывает приложение', (tester) async {
    final store = InMemorySessionStore(deviceId: 'device-1');
    final api = FakeAuthApi(
      loginResponse: AuthResponse(
        userId: 'user-1',
        deviceId: 'device-1',
        accessToken: 'access',
        accessExpiresAt: DateTime.now().toUtc().add(
          const Duration(minutes: 15),
        ),
        refreshToken: 'refresh',
        refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          authApiProvider.overrideWithValue(api),
          notesProvider.overrideWith(
            (ref) => Stream<List<Note>>.value(const []),
          ),
          syncControllerProvider.overrideWith(NoopSyncController.new),
        ],
        child: const ZadachnikApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('authEmail')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('authEmail')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('authPassword')),
      'password-1234',
    );
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет заметок'), findsOneWidget);
    expect(api.loginCalls, 1);
  });
}
