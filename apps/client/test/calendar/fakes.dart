import 'package:zadachnik_client/features/calendar/application/reminder_scheduler.dart';
import 'package:zadachnik_client/features/calendar/domain/task_reminder.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

class FakeReminderScheduler implements ReminderScheduler {
  bool permission = true;
  int initializeCalls = 0;
  int permissionCalls = 0;
  final List<TaskReminder> scheduled = [];
  final List<String> cancelled = [];
  int cancelAllCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> requestPermission() async {
    permissionCalls += 1;
    return permission;
  }

  @override
  Future<void> schedule({
    required TaskReminder reminder,
    required Task task,
  }) async {
    scheduled
      ..removeWhere((item) => item.id == reminder.id)
      ..add(reminder);
  }

  @override
  Future<void> cancel(String reminderId) async {
    cancelled.add(reminderId);
    scheduled.removeWhere((item) => item.id == reminderId);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls += 1;
    scheduled.clear();
  }
}
