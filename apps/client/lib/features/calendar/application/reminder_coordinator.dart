import '../data/reminders_repository.dart';
import '../domain/task_reminder.dart';
import '../../tasks/data/tasks_repository.dart';
import 'reminder_scheduler.dart';

class ReminderSaveResult {
  const ReminderSaveResult({
    required this.reminder,
    required this.notificationsAllowed,
  });

  final TaskReminder? reminder;
  final bool notificationsAllowed;
}

/// Связывает локальные напоминания с системными уведомлениями.
class ReminderCoordinator {
  ReminderCoordinator({
    required this.reminders,
    required this.tasks,
    required this.scheduler,
  });

  final RemindersRepository reminders;
  final TasksRepository tasks;
  final ReminderScheduler scheduler;

  /// iOS хранит не более 64 запланированных уведомлений.
  static const maxScheduledNotifications = 64;

  Future<void> initialize() => scheduler.initialize();

  Future<void> reconcile() async {
    await scheduler.initialize();
    await scheduler.cancelAll();
    final allReminders = await reminders.listAllActive();
    final allTasks = await tasks.listAll();
    final taskById = {for (final task in allTasks) task.id: task};
    final now = DateTime.now().toUtc();
    var scheduled = 0;

    for (final reminder in allReminders) {
      final task = taskById[reminder.taskId];
      if (task == null ||
          task.isCancelled ||
          !reminder.remindAt.toUtc().isAfter(now)) {
        await scheduler.cancel(reminder.id);
        continue;
      }
      if (scheduled >= maxScheduledNotifications) {
        continue;
      }
      await scheduler.schedule(reminder: reminder, task: task);
      scheduled += 1;
    }
  }

  Future<ReminderSaveResult> saveForTask(
    String taskId,
    DateTime? remindAt,
  ) async {
    final existing = await reminders.findForTask(taskId);
    final saved = await reminders.saveForTask(taskId, remindAt);
    if (saved == null) {
      if (existing != null) {
        await scheduler.cancel(existing.id);
      }
      return const ReminderSaveResult(
        reminder: null,
        notificationsAllowed: true,
      );
    }

    final task = await tasks.findById(taskId);
    if (task == null || task.isCancelled) {
      await scheduler.cancel(saved.id);
      return ReminderSaveResult(reminder: saved, notificationsAllowed: false);
    }

    final allowed = await scheduler.requestPermission();
    if (allowed) {
      await scheduler.schedule(reminder: saved, task: task);
    } else {
      await scheduler.cancel(saved.id);
    }
    return ReminderSaveResult(reminder: saved, notificationsAllowed: allowed);
  }

  Future<void> cancelForTask(String taskId) async {
    final existing = await reminders.findForTask(taskId);
    if (existing == null) {
      return;
    }
    await reminders.saveForTask(taskId, null);
    await scheduler.cancel(existing.id);
  }
}
