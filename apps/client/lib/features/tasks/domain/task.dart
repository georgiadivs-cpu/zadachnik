/// Задача на единственной TODO-доске.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.laneId,
    required this.systemState,
    required this.categoryId,
    required this.categoryName,
    required this.priority,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.actualStartAt,
    required this.actualEndAt,
    required this.revision,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final String laneId;
  final String systemState;
  final String? categoryId;
  final String? categoryName;
  final String priority;
  final DateTime? plannedStartAt;
  final DateTime? plannedEndAt;
  final DateTime? actualStartAt;
  final DateTime? actualEndAt;
  final int revision;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCancelled => systemState == 'CANCELLED';
}

/// Изменяемые поля задачи. Не содержит id, revision и sync-состояния.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.description,
    required this.laneId,
    required this.categoryId,
    required this.priority,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.actualStartAt,
    required this.actualEndAt,
  });

  final String title;
  final String description;
  final String laneId;
  final String? categoryId;
  final String priority;
  final DateTime? plannedStartAt;
  final DateTime? plannedEndAt;
  final DateTime? actualStartAt;
  final DateTime? actualEndAt;

  factory TaskDraft.fromTask(Task task) => TaskDraft(
    title: task.title,
    description: task.description,
    laneId: task.laneId,
    categoryId: task.categoryId,
    priority: task.priority,
    plannedStartAt: task.plannedStartAt,
    plannedEndAt: task.plannedEndAt,
    actualStartAt: task.actualStartAt,
    actualEndAt: task.actualEndAt,
  );

  TaskDraft copyWith({
    String? title,
    String? description,
    String? laneId,
    String? categoryId,
    String? priority,
    DateTime? plannedStartAt,
    DateTime? plannedEndAt,
    DateTime? actualStartAt,
    DateTime? actualEndAt,
  }) => TaskDraft(
    title: title ?? this.title,
    description: description ?? this.description,
    laneId: laneId ?? this.laneId,
    categoryId: categoryId ?? this.categoryId,
    priority: priority ?? this.priority,
    plannedStartAt: plannedStartAt ?? this.plannedStartAt,
    plannedEndAt: plannedEndAt ?? this.plannedEndAt,
    actualStartAt: actualStartAt ?? this.actualStartAt,
    actualEndAt: actualEndAt ?? this.actualEndAt,
  );
}
