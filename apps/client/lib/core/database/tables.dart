import 'package:drift/drift.dart';

/// Категории данных. Категория не является статусом задачи.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Markdown-заметка. Удаление представлено через [deletedAt].
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get contentMarkdown => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('PENDING'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Локальная очередь операций для будущей синхронизации.
class SyncOutbox extends Table {
  TextColumn get operationId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationType => text()();
  TextColumn get payload => text()();
  IntColumn get baseRevision => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

/// Курсор синхронизации по пользователю.
class SyncStates extends Table {
  TextColumn get userId => text()();
  TextColumn get cursor => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

/// Дорожка TODO-доски. Дорожка — рабочий статус задачи.
@DataClassName('LaneRow')
class Lanes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get sortOrder => integer()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('SYNCED'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Задача на единственной доске.
@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get laneId => text().references(Lanes, #id)();
  TextColumn get systemState =>
      text().withDefault(const Constant('ACTIVE'))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get priority => text().withDefault(const Constant('NORMAL'))();
  DateTimeColumn get plannedStartAt => dateTime().nullable()();
  DateTimeColumn get plannedEndAt => dateTime().nullable()();
  DateTimeColumn get actualStartAt => dateTime().nullable()();
  DateTimeColumn get actualEndAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('PENDING'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Локальная история перемещений задачи между дорожками.
@DataClassName('TaskHistoryRow')
class TaskStatusHistory extends Table {
  IntColumn get sequence => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get taskId => text()();
  TextColumn get fromLaneId => text().nullable()();
  TextColumn get toLaneId => text()();
  TextColumn get operationId => text().nullable()();
  DateTimeColumn get changedAt => dateTime()();
  TextColumn get source => text()();

  @override
  Set<Column<Object>> get primaryKey => {sequence};
}

/// Одно активное напоминание задачи. Время хранится в UTC.
@DataClassName('ReminderRow')
class TaskReminders extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  DateTimeColumn get remindAt => dateTime()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('PENDING'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Метаданные вложения. Сам файл лежит в папке приложения или на сервере.
@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
  TextColumn get localPath => text().nullable()();
  IntColumn get serverRevision => integer().withDefault(const Constant(0))();
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('PENDING'))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Серверная версия сущности при конфликте.
class Conflicts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  TextColumn get serverPayload => text()();
  IntColumn get serverVersion => integer()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
