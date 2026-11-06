import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/application/calendar_providers.dart';
import '../../calendar/application/reminder_coordinator.dart';
import '../data/tasks_repository.dart';
import 'tasks_providers.dart';
import '../domain/task.dart';

class TaskEditorOutcome {
  const TaskEditorOutcome({
    required this.taskId,
    required this.notificationsAllowed,
  });

  final String taskId;
  final bool notificationsAllowed;
}

/// Сохраняет задачу и её единственное напоминание согласованно.
class TaskEditorService {
  TaskEditorService(this._tasks, this._reminders);

  final TasksRepository _tasks;
  final ReminderCoordinator _reminders;

  Future<TaskEditorOutcome> save({
    required TaskDraft draft,
    required DateTime? reminderAt,
    Task? task,
  }) async {
    final taskId = task?.id ?? await _tasks.create(draft);
    if (task != null) {
      await _tasks.updateLocal(task, draft);
    }
    final reminder = await _reminders.saveForTask(taskId, reminderAt);
    return TaskEditorOutcome(
      taskId: taskId,
      notificationsAllowed: reminder.notificationsAllowed,
    );
  }
}

final taskEditorServiceProvider = Provider<TaskEditorService>((ref) {
  return TaskEditorService(
    ref.watch(tasksRepositoryProvider),
    ref.watch(reminderCoordinatorProvider),
  );
});
