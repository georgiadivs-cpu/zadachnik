import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/application/calendar_providers.dart';
import '../../calendar/application/reminder_coordinator.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/data/notes_repository.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../tasks/domain/task.dart';
import '../data/ai_repository.dart';
import '../domain/ai_models.dart';
import 'ai_providers.dart';

class AiApprovalService {
  AiApprovalService({
    required this.notes,
    required this.tasks,
    required this.reminders,
    required this.repository,
  });

  final NotesRepository notes;
  final TasksRepository tasks;
  final ReminderCoordinator reminders;
  final AiRepository repository;

  Future<AiApplyResult> approve(AiProposal proposal) async {
    try {
      await _validate(proposal.changes);
      for (final change in proposal.changes) {
        await _apply(change);
      }
      await repository.markDecided(
        id: proposal.id,
        status: 'APPLIED',
        message: 'Изменения применены после подтверждения',
        executed: true,
      );
      return const AiApplyResult(success: true, message: 'Изменения применены');
    } on AiStaleProposal catch (error) {
      await repository.markDecided(
        id: proposal.id,
        status: 'STALE',
        error: error.message,
      );
      return AiApplyResult(success: false, stale: true, message: error.message);
    } on Object catch (error) {
      await repository.markDecided(
        id: proposal.id,
        status: 'FAILED',
        error: error.toString(),
      );
      return AiApplyResult(
        success: false,
        message: 'Не удалось применить предложение: $error',
      );
    }
  }

  Future<void> reject(AiProposal proposal) {
    return repository.markDecided(
      id: proposal.id,
      status: 'REJECTED',
      message: 'Отклонено пользователем',
    );
  }

  Future<void> _validate(List<AiChange> changes) async {
    for (final change in changes) {
      switch (change.type) {
        case AiChangeType.moveTask:
        case AiChangeType.updateTaskDates:
          final task = await _taskFor(change);
          _checkTaskVersion(task, change);
          if (change.type == AiChangeType.moveTask) {
            final fromLane = change.data['fromLaneId'] as String?;
            if (task.laneId != fromLane) {
              throw const AiStaleProposal(
                'Задача уже перемещена. Сформируйте предложение заново.',
              );
            }
          }
        case AiChangeType.addReminder:
          await _taskFor(change);
        case AiChangeType.createNote:
          break;
        case AiChangeType.appendNote:
          final id = change.targetId;
          final note = id == null ? null : await notes.findById(id);
          if (note == null ||
              note.updatedAt.toUtc().toIso8601String() !=
                  change.data['expectedUpdatedAt']) {
            throw const AiStaleProposal(
              'Заметка изменилась. Сформируйте предложение заново.',
            );
          }
      }
    }
  }

  Future<void> _apply(AiChange change) async {
    switch (change.type) {
      case AiChangeType.moveTask:
        final task = await _taskFor(change);
        await tasks.moveToLane(task, change.data['toLaneId'] as String);
      case AiChangeType.updateTaskDates:
        final task = await _taskFor(change);
        final start = DateTime.parse(change.data['plannedStartAt'] as String);
        final end = DateTime.parse(change.data['plannedEndAt'] as String);
        await tasks.updateLocal(
          task,
          TaskDraft.fromTask(task)
              .copyWith(plannedStartAt: start, plannedEndAt: end),
        );
      case AiChangeType.addReminder:
        final task = await _taskFor(change);
        final remindAt = DateTime.parse(change.data['remindAt'] as String);
        await reminders.saveForTask(task.id, remindAt);
      case AiChangeType.createNote:
        await notes.create(
          title: change.data['title'] as String,
          contentMarkdown: change.data['contentMarkdown'] as String? ?? '',
          categoryId: change.data['categoryId'] as String? ?? 'personal',
        );
      case AiChangeType.appendNote:
        final id = change.targetId;
        final note = id == null ? null : await notes.findById(id);
        if (note == null) {
          throw const AiStaleProposal('Заметка больше не существует.');
        }
        await notes.updateLocal(
          note: note,
          title: note.title,
          contentMarkdown: change.data['contentMarkdown'] as String,
          categoryId: note.categoryId ?? 'personal',
        );
    }
  }

  Future<Task> _taskFor(AiChange change) async {
    final id = change.targetId;
    final task = id == null ? null : await tasks.findById(id);
    if (task == null) {
      throw const AiStaleProposal('Задача больше не существует.');
    }
    return task;
  }

  void _checkTaskVersion(Task task, AiChange change) {
    final expectedRevision = change.data['expectedRevision'] as int?;
    final expectedUpdatedAt = change.data['expectedUpdatedAt'] as String?;
    if (task.revision != expectedRevision ||
        task.updatedAt.toUtc().toIso8601String() != expectedUpdatedAt) {
      throw const AiStaleProposal(
        'Задача изменилась. Сформируйте предложение заново.',
      );
    }
  }
}

final aiApprovalServiceProvider = Provider<AiApprovalService>((ref) {
  return AiApprovalService(
    notes: ref.watch(notesRepositoryProvider),
    tasks: ref.watch(tasksRepositoryProvider),
    reminders: ref.watch(reminderCoordinatorProvider),
    repository: ref.watch(aiRepositoryProvider),
  );
});
