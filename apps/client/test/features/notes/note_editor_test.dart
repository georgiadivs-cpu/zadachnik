import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/notes/application/notes_providers.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/notes/domain/note.dart';
import 'package:zadachnik_client/features/notes/presentation/note_editor_page.dart';
import 'package:zadachnik_client/features/notes/presentation/notes_page.dart';

void main() {
  late AppDatabase database;
  late NotesRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = NotesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Note> seedNote({String content = '# Планы\n\nПервый текст'}) async {
    final id = await repository.create(
      title: 'Планы',
      contentMarkdown: content,
      categoryId: 'work',
    );
    final create = (await database.select(database.syncOutbox).get()).single;
    await repository.applyPushSuccess(
      operationId: create.operationId,
      noteId: id,
      revision: 1,
      sentPayload: create.payload,
    );
    return (await repository.findById(id))!;
  }

  Widget app(Widget home) {
    return ProviderScope(
      overrides: [notesRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: home),
    );
  }

  testWidgets('редактирует и сохраняет заметку', (tester) async {
    final note = await seedNote();
    await tester.pumpWidget(app(NoteEditorPage(note: note)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('noteTitleField')),
      'Обновлённые планы',
    );
    await tester.enterText(
      find.byKey(const Key('noteContentField')),
      '# Обновлённые планы\n\nНовый текст',
    );
    await tester.pump();

    expect(find.text('Есть несохранённые изменения'), findsWidgets);
    await tester.tap(find.byKey(const Key('noteSaveButton')));
    await tester.pumpAndSettle();

    final saved = await repository.findById(note.id);
    expect(saved?.title, 'Обновлённые планы');
    expect(saved?.contentMarkdown, contains('Новый текст'));
    expect(saved?.syncStatus, 'PENDING');
    expect(await database.select(database.syncOutbox).get(), hasLength(1));
  });

  testWidgets('автосохранение записывает изменения без кнопки', (tester) async {
    final note = await seedNote();
    await tester.pumpWidget(app(NoteEditorPage(note: note)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('noteContentField')),
      '# Автосохранение',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    final saved = await repository.findById(note.id);
    expect(saved?.contentMarkdown, '# Автосохранение');
    expect(saved?.syncStatus, 'PENDING');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('переключает предпросмотр Markdown', (tester) async {
    final note = await seedNote();
    await tester.pumpWidget(app(NoteEditorPage(note: note)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notePreviewTab')));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('Первый текст'), findsWidgets);
  });

  testWidgets('не загружает внешние изображения из Markdown', (tester) async {
    final note = await seedNote(
      content: '![схема](https://example.com/private.png)',
    );
    await tester.pumpWidget(app(NoteEditorPage(note: note)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notePreviewTab')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('схема'), findsOneWidget);
  });

  testWidgets('создаёт новую заметку из пустого редактора', (tester) async {
    await tester.pumpWidget(app(const NoteEditorPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('noteTitleField')),
      'Новая заметка',
    );
    await tester.enterText(
      find.byKey(const Key('noteContentField')),
      'Содержимое',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('noteSaveButton')));
    await tester.pumpAndSettle();

    final notes = await database.select(database.notes).get();
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Новая заметка');
    expect(notes.single.contentMarkdown, 'Содержимое');
  });

  testWidgets('не выходит с несохранёнными изменениями без выбора', (
    tester,
  ) async {
    final note = await seedNote();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('openEditor'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openEditor')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('noteTitleField')),
      'Несохранённое',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('noteBackButton')));
    await tester.pumpAndSettle();

    expect(find.text('Несохранённые изменения'), findsOneWidget);
    await tester.tap(find.text('Выйти без сохранения'));
    await tester.pumpAndSettle();

    expect(find.text('Открыть'), findsOneWidget);
    expect((await repository.findById(note.id))?.title, 'Планы');
  });

  testWidgets('корректно помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final note = await seedNote();

    await tester.pumpWidget(app(NoteEditorPage(note: note)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noteTitleField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нажатие на карточку открывает редактор', (tester) async {
    final note = await seedNote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(repository),
          notesProvider.overrideWith((ref) => Stream.value([note])),
        ],
        child: const MaterialApp(home: NotesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(note.title));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noteTitleField')), findsOneWidget);
    expect(find.byKey(const Key('noteContentField')), findsOneWidget);
  });
}
