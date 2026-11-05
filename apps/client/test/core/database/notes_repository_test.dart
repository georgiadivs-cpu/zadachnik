import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';

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

  test('создаёт заметку локально и ставит операцию в outbox', () async {
    final id = await repository.create(
      title: 'Первая заметка',
      contentMarkdown: '# Заголовок\n\nТекст',
      categoryId: 'personal',
    );

    final notes = await repository.watchAll().first;
    expect(notes, hasLength(1));
    expect(notes.single.id, id);
    expect(notes.single.title, 'Первая заметка');
    expect(notes.single.categoryName, 'Личное');
    expect(notes.single.contentMarkdown, contains('# Заголовок'));

    final operations = await database.select(database.syncOutbox).get();
    expect(operations, hasLength(1));
    expect(operations.single.entityType, 'NOTE');
    expect(operations.single.entityId, id);
    expect(operations.single.operationType, 'CREATE');

    final categories = await database.select(database.categories).get();
    expect(
      categories.map((category) => category.id),
      containsAll(['work', 'personal', 'family']),
    );
  });

  test('отклоняет заметку с пустым заголовком', () async {
    expect(
      () => repository.create(
        title: '   ',
        contentMarkdown: '',
        categoryId: 'personal',
      ),
      throwsArgumentError,
    );

    expect(await database.select(database.syncOutbox).get(), isEmpty);
  });

  test('последовательные правки объединяются в одну операцию UPDATE', () async {
    final id = await repository.create(
      title: 'Черновик',
      contentMarkdown: 'Первый текст',
      categoryId: 'personal',
    );
    final create = (await database.select(database.syncOutbox).get()).single;
    await repository.applyPushSuccess(
      operationId: create.operationId,
      noteId: id,
      revision: 1,
      sentPayload: create.payload,
    );
    final note = (await repository.findById(id))!;

    await repository.updateLocal(
      note: note,
      title: 'Рабочая заметка',
      contentMarkdown: 'Второй текст',
      categoryId: 'work',
    );
    await repository.updateLocal(
      note: note,
      title: 'Итоговая заметка',
      contentMarkdown: 'Третий текст',
      categoryId: 'family',
    );

    final operations = await database.select(database.syncOutbox).get();
    expect(operations, hasLength(1));
    expect(operations.single.operationType, 'UPDATE');
    expect(operations.single.baseRevision, 1);
    expect(
      (jsonDecode(operations.single.payload) as Map<String, dynamic>)['title'],
      'Итоговая заметка',
    );

    final updated = await repository.findById(id);
    expect(updated?.title, 'Итоговая заметка');
    expect(updated?.contentMarkdown, 'Третий текст');
    expect(updated?.categoryName, 'Семья');
    expect(updated?.syncStatus, 'PENDING');
  });

  test(
    'удаление синхронизированной заметки создаёт DELETE с baseRevision',
    () async {
      final id = await repository.create(
        title: 'Удаляемая',
        contentMarkdown: '',
        categoryId: 'personal',
      );
      final create = (await database.select(database.syncOutbox).get()).single;
      await repository.applyPushSuccess(
        operationId: create.operationId,
        noteId: id,
        revision: 1,
        sentPayload: create.payload,
      );
      final note = (await repository.findById(id))!;
      await repository.updateLocal(
        note: note,
        title: 'Удаляемая',
        contentMarkdown: 'Текст',
        categoryId: 'personal',
      );
      await repository.deleteLocal(note);

      final operations = await database.select(database.syncOutbox).get();
      expect(operations, hasLength(1));
      expect(operations.single.operationType, 'DELETE');
      expect(operations.single.baseRevision, 1);
      expect(operations.single.payload, '{}');
      expect(await repository.watchAll().first, isEmpty);
    },
  );

  test('удаление неотправленного создания очищает заметку и outbox', () async {
    final id = await repository.create(
      title: 'Неотправленная',
      contentMarkdown: '',
      categoryId: 'personal',
    );
    final note = (await repository.findById(id))!;
    await repository.deleteLocal(note);

    expect(await repository.watchAll().first, isEmpty);
    expect(await database.select(database.syncOutbox).get(), isEmpty);
  });
}
