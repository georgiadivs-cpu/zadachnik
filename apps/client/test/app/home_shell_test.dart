import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/app/home_shell.dart';
import 'package:zadachnik_client/features/notes/application/notes_providers.dart';
import 'package:zadachnik_client/features/notes/domain/note.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';

import '../auth/fakes.dart';

void main() {
  testWidgets('показывает разделы и переключает вкладки', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesProvider.overrideWith(
            (ref) => Stream<List<Note>>.value(const []),
          ),
          syncControllerProvider.overrideWith(NoopSyncController.new),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Пока нет заметок'), findsOneWidget);
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Календарь'), findsOneWidget);
    expect(find.text('Гант'), findsOneWidget);

    await tester.tap(find.text('Задачи'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Одна доска'), findsOneWidget);
  });
}
