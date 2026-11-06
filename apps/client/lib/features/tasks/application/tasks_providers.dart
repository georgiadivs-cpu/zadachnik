import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/lanes_repository.dart';
import '../data/tasks_repository.dart';
import '../domain/lane.dart';
import '../domain/task.dart';

final lanesRepositoryProvider = Provider<LanesRepository>((ref) {
  return LanesRepository(ref.watch(appDatabaseProvider));
});

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(ref.watch(appDatabaseProvider));
});

final lanesProvider = StreamProvider<List<Lane>>((ref) {
  return ref.watch(lanesRepositoryProvider).watchAll();
});

final tasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(tasksRepositoryProvider).watchAll();
});
