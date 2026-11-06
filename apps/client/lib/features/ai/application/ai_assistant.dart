import 'package:uuid/uuid.dart';

import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note.dart';
import '../../tasks/data/lanes_repository.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../tasks/domain/lane.dart';
import '../../tasks/domain/task.dart';
import '../data/ai_repository.dart';
import '../domain/ai_models.dart';

/// Локальный ассистент с ограниченным набором команд.
/// Он не обращается к внешним моделям и не исполняет содержимое заметок.
class AiAssistant {
  AiAssistant({
    required this.notes,
    required this.tasks,
    required this.lanes,
    required this.repository,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final NotesRepository notes;
  final TasksRepository tasks;
  final LanesRepository lanes;
  final AiRepository repository;
  final Uuid _uuid;

  Future<AiResponse> respond(String rawPrompt) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) {
      return const AiResponse(message: _help);
    }
    final lower = prompt.toLowerCase();
    final allTasks = await tasks.listAll();
    final allLanes = await lanes.listAll();
    final allNotes = await notes.listAll();

    if (_containsAny(lower, ['что сегодня', 'задачи на сегодня'])) {
      return _todaySummary(allTasks);
    }
    if (_containsAny(lower, ['сколько задач', 'статистика задач'])) {
      return _taskStats(allTasks);
    }
    if (_containsAny(lower, ['просроченные', 'просрочка'])) {
      return _overdueSummary(allTasks);
    }
    final summaryMatch = RegExp(
      r'''^суммируй\s+заметку\s+[«"']?(.+?)[»"']?$''',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (summaryMatch != null) {
      return _noteSummary(allNotes, summaryMatch.group(1)!.trim());
    }

    final doneMatch = RegExp(
      r'^(?:отметь|заверши)\s+(?:задачу\s+)?(.+?)\s+(?:выполненной|готовой|завершённой|готово)$',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (doneMatch != null) {
      return _moveTaskProposal(
        allTasks,
        allLanes,
        doneMatch.group(1)!,
        allLanes.isEmpty ? null : allLanes.last,
        prompt,
        title: 'Завершение задачи',
      );
    }

    final laneMatch = RegExp(
      r'^перенеси\s+(?:задачу\s+)?(.+?)\s+в\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (laneMatch != null) {
      final lane = _matchLane(allLanes, laneMatch.group(2)!);
      if (lane == null) {
        return AiResponse(
          message: 'Не нашёл дорожку «${laneMatch.group(2)!.trim()}».',
        );
      }
      return _moveTaskProposal(
        allTasks,
        allLanes,
        laneMatch.group(1)!,
        lane,
        prompt,
        title: 'Перемещение задачи',
      );
    }

    final dateMatch = RegExp(
      r'^перенеси\s+(?:задачу\s+)?(.+?)\s+на\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (dateMatch != null) {
      final date = _parseDateTime(dateMatch.group(2)!, defaultHour: 0);
      if (date == null) {
        return const AiResponse(
          message:
              'Не понял дату. Используйте «сегодня», «завтра» или 12.11.2026.',
        );
      }
      return _rescheduleProposal(allTasks, dateMatch.group(1)!, date, prompt);
    }

    final reminderMatch = RegExp(
      r'^(?:добавь\s+напоминание|напомни)\s+(?:для\s+)?(?:задачи\s+)?(.+?)\s+на\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (reminderMatch != null) {
      final date = _parseDateTime(reminderMatch.group(2)!, defaultHour: 9);
      if (date == null) {
        return const AiResponse(message: 'Не понял дату напоминания.');
      }
      return _reminderProposal(allTasks, reminderMatch.group(1)!, date, prompt);
    }

    final createMatch = RegExp(
      r'''^создай\s+заметку\s+[«"']?(.+?)[»"']?(?:\s+с\s+текстом\s+[«"']?(.+?)[»"']?)?$''',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (createMatch != null) {
      return _createNoteProposal(
        createMatch.group(1)!.trim(),
        createMatch.group(2)?.trim() ?? '',
        prompt,
      );
    }

    final appendMatch = RegExp(
      r'''^добавь\s+в\s+заметку\s+[«"']?(.+?)[»"']?\s+(?:пункт|строку|текст)\s+[«"']?(.+?)[»"']?$''',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (appendMatch != null) {
      return _appendNoteProposal(
        allNotes,
        appendMatch.group(1)!,
        appendMatch.group(2)!,
        prompt,
      );
    }

    return const AiResponse(message: _help);
  }

  Future<AiResponse> _moveTaskProposal(
    List<Task> allTasks,
    List<Lane> allLanes,
    String taskQuery,
    Lane? target,
    String prompt, {
    required String title,
  }) async {
    final task = _matchTask(allTasks, taskQuery);
    if (task == null) {
      return AiResponse(message: _notFoundMessage('задачу', taskQuery));
    }
    if (target == null) {
      return const AiResponse(message: 'Не нашёл дорожку.');
    }
    final current = allLanes.where((lane) => lane.id == task.laneId);
    final before = current.isEmpty ? 'Без дорожки' : current.first.name;
    if (task.laneId == target.id) {
      return AiResponse(
        message: 'Задача уже находится в дорожке «${target.name}».',
      );
    }
    final proposal = AiProposal(
      id: _uuid.v4(),
      prompt: prompt,
      title: title,
      explanation:
          'Переместить задачу «${task.title}» из «$before» в «${target.name}».',
      impact:
          'Изменится рабочая дорожка задачи. История перемещения сохранится.',
      changes: [
        AiChange(
          type: AiChangeType.moveTask,
          targetId: task.id,
          targetTitle: task.title,
          field: 'Дорожка',
          before: before,
          after: target.name,
          data: {
            'expectedRevision': task.revision,
            'expectedUpdatedAt': task.updatedAt.toUtc().toIso8601String(),
            'fromLaneId': task.laneId,
            'toLaneId': target.id,
          },
        ),
      ],
    );
    await repository.createProposal(proposal);
    return AiResponse(
      message: 'Подготовил предложение. Оно не применено до подтверждения.',
      proposal: proposal,
    );
  }

  Future<AiResponse> _rescheduleProposal(
    List<Task> allTasks,
    String taskQuery,
    DateTime date,
    String prompt,
  ) async {
    final task = _matchTask(allTasks, taskQuery);
    if (task == null) {
      return AiResponse(message: _notFoundMessage('задачу', taskQuery));
    }
    final after = DateTime(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
    );
    final proposal = AiProposal(
      id: _uuid.v4(),
      prompt: prompt,
      title: 'Перенос задачи',
      explanation: 'Изменить плановую дату задачи «${task.title}».',
      impact: 'Плановые даты будут заменены. Фактические даты не изменятся.',
      changes: [
        AiChange(
          type: AiChangeType.updateTaskDates,
          targetId: task.id,
          targetTitle: task.title,
          field: 'Плановые даты',
          before: _taskDateRange(task),
          after: _formatDateTime(after),
          data: {
            'expectedRevision': task.revision,
            'expectedUpdatedAt': task.updatedAt.toUtc().toIso8601String(),
            'plannedStartAt': after.toUtc().toIso8601String(),
            'plannedEndAt': after.toUtc().toIso8601String(),
          },
        ),
      ],
    );
    await repository.createProposal(proposal);
    return AiResponse(
      message: 'Подготовил перенос даты. Подтвердите или отклоните.',
      proposal: proposal,
    );
  }

  Future<AiResponse> _reminderProposal(
    List<Task> allTasks,
    String taskQuery,
    DateTime date,
    String prompt,
  ) async {
    final task = _matchTask(allTasks, taskQuery);
    if (task == null) {
      return AiResponse(message: _notFoundMessage('задачу', taskQuery));
    }
    final proposal = AiProposal(
      id: _uuid.v4(),
      prompt: prompt,
      title: 'Напоминание',
      explanation: 'Добавить напоминание к задаче «${task.title}».',
      impact: 'Появится локальное уведомление. Существующее напоминание будет заменено.',
      changes: [
        AiChange(
          type: AiChangeType.addReminder,
          targetId: task.id,
          targetTitle: task.title,
          field: 'Напоминание',
          before: '—',
          after: _formatDateTime(date),
          data: {'remindAt': date.toUtc().toIso8601String()},
        ),
      ],
    );
    await repository.createProposal(proposal);
    return AiResponse(
      message: 'Подготовил напоминание. Подтвердите или отклоните.',
      proposal: proposal,
    );
  }

  Future<AiResponse> _createNoteProposal(
    String title,
    String content,
    String prompt,
  ) async {
    if (title.isEmpty) {
      return const AiResponse(message: 'Укажите заголовок заметки.');
    }
    final proposal = AiProposal(
      id: _uuid.v4(),
      prompt: prompt,
      title: 'Новая заметка',
      explanation: 'Создать заметку «$title».',
      impact: 'Заметка сохранится локально и попадёт в очередь синхронизации.',
      changes: [
        AiChange(
          type: AiChangeType.createNote,
          targetId: null,
          targetTitle: title,
          field: 'Заметка',
          before: '—',
          after: title,
          data: {
            'title': title,
            'contentMarkdown': content,
            'categoryId': 'personal',
          },
        ),
      ],
    );
    await repository.createProposal(proposal);
    return AiResponse(
      message: 'Подготовил заметку. Подтвердите или отклоните.',
      proposal: proposal,
    );
  }

  Future<AiResponse> _appendNoteProposal(
    List<Note> allNotes,
    String noteQuery,
    String text,
    String prompt,
  ) async {
    final note = _matchNote(allNotes, noteQuery);
    if (note == null) {
      return AiResponse(message: _notFoundMessage('заметку', noteQuery));
    }
    final line = text.trim();
    if (line.isEmpty) {
      return const AiResponse(message: 'Укажите текст пункта.');
    }
    final content = '${note.contentMarkdown.trimRight()}\n- $line';
    final proposal = AiProposal(
      id: _uuid.v4(),
      prompt: prompt,
      title: 'Дополнение заметки',
      explanation: 'Добавить строку в заметку «${note.title}».',
      impact:
          'Markdown-содержимое заметки изменится, остальной текст сохранится.',
      changes: [
        AiChange(
          type: AiChangeType.appendNote,
          targetId: note.id,
          targetTitle: note.title,
          field: 'Markdown',
          before: _shorten(note.contentMarkdown, 90),
          after: _shorten(content, 90),
          data: {
            'expectedRevision': note.revision,
            'expectedUpdatedAt': note.updatedAt.toUtc().toIso8601String(),
            'contentMarkdown': content,
            'append': line,
          },
        ),
      ],
    );
    await repository.createProposal(proposal);
    return AiResponse(
      message: 'Подготовил дополнение заметки. Подтвердите или отклоните.',
      proposal: proposal,
    );
  }

  AiResponse _todaySummary(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = tasks.where((task) {
      if (task.isCancelled || task.plannedStartAt == null) {
        return false;
      }
      final start = task.plannedStartAt!.toLocal();
      final end = (task.plannedEndAt ?? task.plannedStartAt!).toLocal();
      final first = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      return !today.isBefore(first) && !today.isAfter(last);
    }).toList();
    if (items.isEmpty) {
      return const AiResponse(
        message: 'На сегодня задач с плановыми датами нет.',
      );
    }
    return AiResponse(
      message:
          'На сегодня ${items.length} задач:\n'
          '${items.take(8).map((task) => '• ${task.title}').join('\n')}',
    );
  }

  AiResponse _taskStats(List<Task> tasks) {
    final active = tasks.where((task) => !task.isCancelled).length;
    return AiResponse(
      message:
          'Активных задач: $active.\n'
          'Просроченных: ${_overdueTasks(tasks).length}.\n'
          'Всего с учётом отменённых: ${tasks.length}.',
    );
  }

  AiResponse _overdueSummary(List<Task> tasks) {
    final overdue = _overdueTasks(tasks);
    if (overdue.isEmpty) {
      return const AiResponse(message: 'Просроченных задач нет.');
    }
    return AiResponse(
      message:
          'Просрочено ${overdue.length}:\n'
          '${overdue.take(10).map((task) => '• ${task.title}').join('\n')}',
    );
  }

  AiResponse _noteSummary(List<Note> notes, String query) {
    final note = _matchNote(notes, query);
    if (note == null) {
      return AiResponse(message: _notFoundMessage('заметку', query));
    }
    final text = note.contentMarkdown
        .replaceAll(RegExp(r'[#>*_`\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final summary = text.length <= 260 ? text : '${text.substring(0, 257)}…';
    return AiResponse(message: 'Кратко по заметке «${note.title}»:\n$summary');
  }

  List<Task> _overdueTasks(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return tasks.where((task) {
      if (task.isCancelled || task.plannedEndAt == null) {
        return false;
      }
      final end = task.plannedEndAt!.toLocal();
      final endDate = DateTime(end.year, end.month, end.day);
      return endDate.isBefore(today) && task.actualEndAt == null;
    }).toList();
  }

  static Task? _matchTask(List<Task> tasks, String query) {
    final normalized = _clean(query).toLowerCase();
    final exact = tasks.where((task) => task.title.toLowerCase() == normalized);
    if (exact.length == 1) {
      return exact.first;
    }
    final contains = tasks
        .where((task) => task.title.toLowerCase().contains(normalized))
        .toList();
    return contains.length == 1 ? contains.first : null;
  }

  static Note? _matchNote(List<Note> notes, String query) {
    final normalized = _clean(query).toLowerCase();
    final exact = notes.where((note) => note.title.toLowerCase() == normalized);
    if (exact.length == 1) {
      return exact.first;
    }
    final contains = notes
        .where((note) => note.title.toLowerCase().contains(normalized))
        .toList();
    return contains.length == 1 ? contains.first : null;
  }

  static Lane? _matchLane(List<Lane> lanes, String query) {
    final normalized = _clean(query).toLowerCase();
    for (final lane in lanes) {
      if (lane.name.toLowerCase() == normalized) {
        return lane;
      }
    }
    final contains = lanes
        .where((lane) => lane.name.toLowerCase().contains(normalized))
        .toList();
    return contains.length == 1 ? contains.first : null;
  }

  static String _notFoundMessage(String kind, String query) {
    return 'Не нашёл $kind «${_clean(query)}». '
        'Уточните название среди доступных вариантов.';
  }

  static String _clean(String value) {
    var result = value.trim();
    while (result.length >= 2 &&
        const {'«', '»', '"', "'"}.contains(result[0]) &&
        const {'«', '»', '"', "'"}.contains(result[result.length - 1])) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result;
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  static String _taskDateRange(Task task) {
    if (task.plannedStartAt == null && task.plannedEndAt == null) {
      return '—';
    }
    if (task.plannedStartAt != null && task.plannedEndAt != null) {
      return '${_formatDateTime(task.plannedStartAt!.toLocal())} — '
          '${_formatDateTime(task.plannedEndAt!.toLocal())}';
    }
    return _formatDateTime(
      (task.plannedStartAt ?? task.plannedEndAt)!.toLocal(),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _shorten(String value, int max) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= max
        ? compact
        : '${compact.substring(0, max - 1)}…';
  }

  static DateTime? _parseDateTime(String raw, {required int defaultHour}) {
    final lower = raw.trim().toLowerCase();
    final now = DateTime.now();
    final hasTime = RegExp(r'(\d{1,2}):(\d{2})').hasMatch(lower);
    var date = DateTime(now.year, now.month, now.day);

    if (lower.contains('послезавтра')) {
      date = date.add(const Duration(days: 2));
    } else if (lower.contains('завтра')) {
      date = date.add(const Duration(days: 1));
    } else {
      final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(lower);
      final dotted = RegExp(r'(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?')
          .firstMatch(lower);
      if (iso != null) {
        date = DateTime(
          int.parse(iso.group(1)!),
          int.parse(iso.group(2)!),
          int.parse(iso.group(3)!),
        );
      } else if (dotted != null) {
        final year = dotted.group(3) == null
            ? now.year
            : int.parse(dotted.group(3)!);
        date = DateTime(
          year < 100 ? 2000 + year : year,
          int.parse(dotted.group(1)!),
          int.parse(dotted.group(2)!),
        );
      } else if (!lower.contains('сегодня') && !hasTime) {
        return null;
      }
    }

    final time = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(lower);
    final hour = time == null ? defaultHour : int.parse(time.group(1)!);
    final minute = time == null ? 0 : int.parse(time.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static const _help =
      'Я локальный ассистент. Понимаю команды:\n'
      '• «перенеси задачу X в дорожку Y»\n'
      '• «перенеси задачу X на завтра»\n'
      '• «добавь напоминание X на 12.11.2026 14:00»\n'
      '• «создай заметку X»\n'
      '• «добавь в заметку X пункт Y»\n'
      '• «что сегодня», «сколько задач», «просроченные»\n'
      '• «суммируй заметку X»';
}
