import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../tasks/application/tasks_providers.dart';
import '../data/reminders_repository.dart';
import '../domain/task_reminder.dart';
import 'reminder_coordinator.dart';
import 'reminder_scheduler.dart';

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  return RemindersRepository(ref.watch(appDatabaseProvider));
});

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return LocalReminderScheduler();
});

final reminderCoordinatorProvider = Provider<ReminderCoordinator>((ref) {
  return ReminderCoordinator(
    reminders: ref.watch(remindersRepositoryProvider),
    tasks: ref.watch(tasksRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
  );
});

final remindersProvider = StreamProvider<List<TaskReminder>>((ref) {
  return ref.watch(remindersRepositoryProvider).watchAll();
});
