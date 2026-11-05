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
}
