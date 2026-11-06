/// Запись истории перемещения задачи между дорожками.
class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.id,
    required this.taskId,
    required this.fromLaneId,
    required this.toLaneId,
    required this.operationId,
    required this.changedAt,
    required this.source,
  });

  final String id;
  final String taskId;
  final String? fromLaneId;
  final String toLaneId;
  final String? operationId;
  final DateTime changedAt;
  final String source;
}
