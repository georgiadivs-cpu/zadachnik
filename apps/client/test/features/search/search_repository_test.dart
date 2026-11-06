import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/calendar/data/reminders_repository.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/search/data/search_repository.dart';
import 'package:zadachnik_client/features/search/domain/search_result.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

void main() {
  late AppDatabase database;
  late NotesRepository notes;
  late TasksRepository tasks;
  late RemindersRepository reminders;
  late SearchRepository search;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    notes = NotesRepository(database);
    tasks = TasksRepository(database);
    reminders = RemindersRepository(database);
    search = DriftSearchRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  TaskDraft draft({
    required String title,
    required String description,
    String categoryId = 'work',
    String laneId = DefaultLanes.newLaneId,
    String priority = 'NORMAL',
  }) => TaskDraft(
    title: title,
    description: description,
    laneId: laneId,
    categoryId: categoryId,
    priority: priority,
    plannedStartAt: null,
    plannedEndAt: null,
    actualStartAt: null,
    actualEndAt: null,
  );

  test('ищет заметки по заголовку и содержимому без учёта регистра', () async {
    await notes.create(
      title: 'Планы на неделю',
      contentMarkdown: 'Собрать план и согласовать встречу.',
      categoryId: 'work',
    );
    await notes.create(
      title: 'Идеи',
      contentMarkdown: 'Новый план запуска продукта.',
      categoryId: 'work',
    );

    final results = await search.search(query: 'ПЛАН');

    expect(results, hasLength(2));
    expect(results.first.title, 'Планы на неделю');
    expect(results.first.titleMatched, isTrue);
    expect(
      results.every((result) => result.type == SearchResultType.note),
      isTrue,
    );
  });

  test('ищет задачи по описанию, дорожке и категории', () async {
    await tasks.create(
      draft(
        title: 'Подготовить отчёт',
        description: 'Собрать план и цифры.',
        laneId: DefaultLanes.inProgressLaneId,
        categoryId: 'work',
      ),
    );
    await tasks.create(
      draft(
        title: 'Купить подарок',
        description: 'День рождения.',
        categoryId: 'family',
        priority: 'HIGH',
      ),
    );

    expect(
      (await search.search(query: 'план')).single.title,
      'Подготовить отчёт',
    );
    expect(
      (await search.search(query: 'В работе')).single.title,
      'Подготовить отчёт',
    );
    expect(
      (await search.search(query: 'Семья')).single.title,
      'Купить подарок',
    );
  });

  test('применяет фильтры типа, категории и приоритета', () async {
    await notes.create(
      title: 'Рабочая заметка',
      contentMarkdown: 'План работ',
      categoryId: 'work',
    );
    await tasks.create(
      draft(
        title: 'Рабочая задача',
        description: 'План работ',
        categoryId: 'work',
      ),
    );
    await tasks.create(
      draft(
        title: 'Семейная задача',
        description: 'План выходных',
        categoryId: 'family',
        priority: 'HIGH',
      ),
    );

    final noteOnly = await search.search(
      query: 'план',
      filter: const SearchFilter(type: SearchResultType.note),
    );
    expect(noteOnly, hasLength(1));
    expect(noteOnly.single.type, SearchResultType.note);

    final workOnly = await search.search(
      query: 'план',
      filter: const SearchFilter(categoryId: 'work'),
    );
    expect(workOnly, hasLength(2));
    expect(workOnly.every((result) => result.categoryId == 'work'), isTrue);

    final high = await search.search(
      query: 'план',
      filter: const SearchFilter(highPriority: true),
    );
    expect(high, hasLength(1));
    expect(high.single.title, 'Семейная задача');
  });

  test('возвращает напоминание в метаданных задачи', () async {
    final taskId = await tasks.create(
      draft(title: 'Позвонить', description: 'План звонка'),
    );
    final remindAt = DateTime.utc(2030, 1, 10, 14);
    await reminders.saveForTask(taskId, remindAt);

    final result = (await search.search(query: 'план')).single;

    expect(result.reminderAt, remindAt);
  });

  test('не находит удалённую заметку', () async {
    final id = await notes.create(
      title: 'Удаляемая',
      contentMarkdown: 'План',
      categoryId: 'work',
    );
    final note = (await notes.findById(id))!;
    await notes.deleteLocal(note);

    expect(await search.search(query: 'план'), isEmpty);
  });
}
