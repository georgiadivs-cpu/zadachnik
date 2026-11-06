/// Одно напоминание задачи. [remindAt] хранится в UTC.
class TaskReminder {
  const TaskReminder({
    required this.id,
    required this.taskId,
    required this.remindAt,
    required this.revision,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String taskId;
  final DateTime remindAt;
  final int revision;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
}
