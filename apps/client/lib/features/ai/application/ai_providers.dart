import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../notes/application/notes_providers.dart';
import '../../tasks/application/tasks_providers.dart';
import '../data/ai_repository.dart';
import '../domain/ai_models.dart';
import 'ai_assistant.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(ref.watch(appDatabaseProvider));
});

final aiAssistantProvider = Provider<AiAssistant>((ref) {
  return AiAssistant(
    notes: ref.watch(notesRepositoryProvider),
    tasks: ref.watch(tasksRepositoryProvider),
    lanes: ref.watch(lanesRepositoryProvider),
    repository: ref.watch(aiRepositoryProvider),
  );
});

final aiJournalProvider = StreamProvider<List<AiJournalEntry>>((ref) {
  return ref.watch(aiRepositoryProvider).watchRecent();
});
