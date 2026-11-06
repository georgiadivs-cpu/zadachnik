import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/presentation/search_page.dart';
import '../../sync/application/sync_controller.dart';
import '../application/calendar_providers.dart';
import '../domain/task_reminder.dart';
import '../../tasks/application/task_editor_service.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/domain/lane.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/presentation/task_editor_dialog.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _dayNames = [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];

  late DateTime _month;
  late DateTime _selected;
  String _filter = 'all';
  bool _reminderOnly = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final reminders = ref.watch(remindersProvider);
    final lanes = ref.watch(lanesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь'),
        actions: [
          IconButton(
            key: const Key('calendarSearchButton'),
            tooltip: 'Поиск',
            onPressed: () => openSearchPage(context),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: SafeArea(
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const Center(child: Text('Не удалось загрузить задачи')),
          data: (tasksData) => reminders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) =>
                const Center(child: Text('Не удалось загрузить напоминания')),
            data: (remindersData) => lanes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  const Center(child: Text('Не удалось загрузить дорожки')),
              data: (lanesData) =>
                  _buildCalendar(tasksData, remindersData, lanesData),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar(
    List<Task> tasks,
    List<TaskReminder> reminders,
    List<Lane> lanes,
  ) {
    final taskById = {for (final task in tasks) task.id: task};
    final visibleTasks = tasks.where(_matchesFilter).toList();
    final visibleReminders = reminders
        .where((reminder) => taskById.containsKey(reminder.taskId))
        .where((reminder) {
          final task = taskById[reminder.taskId]!;
          return _matchesFilter(task);
        })
        .toList();
    final reminderTaskIds = reminders.map((item) => item.taskId).toSet();

    return Column(
      children: [
        _header(),
        _filters(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final calendar = _calendarPanel(
                visibleTasks,
                visibleReminders,
                reminderTaskIds,
                lanes,
              );
              final agenda = _agendaPanel(
                visibleTasks,
                visibleReminders,
                taskById,
                lanes,
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: calendar),
                    const SizedBox(width: 14),
                    SizedBox(width: 330, child: agenda),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: calendar),
                  const SizedBox(height: 10),
                  SizedBox(height: 230, child: agenda),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_months[_month.month - 1]} ${_month.year}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Предыдущий месяц',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selected = DateTime(now.year, now.month, now.day);
              });
            },
            child: const Text('Сегодня'),
          ),
          IconButton(
            tooltip: 'Следующий месяц',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.public,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(DateTime.now().timeZoneName, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip('all', 'Все'),
          _filterChip('work', 'Работа'),
          _filterChip('personal', 'Личное'),
          _filterChip('family', 'Семья'),
          FilterChip(
            label: const Text('С напоминаниями'),
            selected: _reminderOnly,
            onSelected: (value) => setState(() => _reminderOnly = value),
            avatar: const Icon(Icons.notifications_active_outlined, size: 16),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Новая задача на выбранный день',
            child: FilledButton.tonalIcon(
              onPressed: () {
                final lanes = ref.read(lanesProvider).value ?? const <Lane>[];
                if (lanes.isNotEmpty) {
                  _openTaskEditor(null, _selected, lanes);
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Задача'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (selected) =>
          setState(() => _filter = selected ? value : 'all'),
    );
  }

  Widget _calendarPanel(
    List<Task> tasks,
    List<TaskReminder> reminders,
    Set<String> reminderTaskIds,
    List<Lane> lanes,
  ) {
    final first = DateTime(_month.year, _month.month, 1);
    final offset = (first.weekday - 1) % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final total = ((offset + days + 6) ~/ 7) * 7;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 0, 16),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                for (final day in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: GridView.builder(
                itemCount: total,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 92,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemBuilder: (context, index) {
                  final dayNumber = index - offset + 1;
                  final date = DateTime(_month.year, _month.month, dayNumber);
                  final inMonth = dayNumber >= 1 && dayNumber <= days;
                  final List<Task> dayTasks = inMonth
                      ? _tasksOn(date, tasks, reminderTaskIds)
                      : const [];
                  final List<TaskReminder> dayReminders = inMonth
                      ? _remindersOn(date, reminders)
                      : const [];
                  return _DayCell(
                    date: date,
                    inMonth: inMonth,
                    selected: _sameDay(date, _selected),
                    today: _sameDay(date, DateTime.now()),
                    tasks: dayTasks,
                    reminders: dayReminders,
                    onTap: () {
                      setState(() {
                        _selected = date;
                        if (!inMonth) {
                          _month = DateTime(date.year, date.month);
                        }
                      });
                    },
                    onOpenTask: (task) => _openTaskEditor(task, date, lanes),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agendaPanel(
    List<Task> tasks,
    List<TaskReminder> reminders,
    Map<String, Task> taskById,
    List<Lane> lanes,
  ) {
    final reminderTaskIds = reminders.map((item) => item.taskId).toSet();
    final dayTasks = _tasksOn(_selected, tasks, reminderTaskIds);
    final dayReminders = _remindersOn(_selected, reminders);
    final dateLabel =
        '${_selected.day} ${_months[_selected.month - 1].toLowerCase()}, '
        '${_dayNames[_selected.weekday - 1]}';

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${dayTasks.length} задач · ${dayReminders.length} напоминаний',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: dayTasks.isEmpty && dayReminders.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'На этот день ничего не запланировано.\n'
                        'Создайте задачу или добавьте напоминание.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: [
                      for (final reminder in dayReminders)
                        _AgendaItem(
                          time: _time(reminder.remindAt),
                          task: taskById[reminder.taskId]!,
                          reminder: true,
                          onTap: () => _openTaskEditor(
                            taskById[reminder.taskId],
                            _selected,
                            lanes,
                          ),
                        ),
                      for (final task in dayTasks)
                        _AgendaItem(
                          time: _taskTime(task),
                          task: task,
                          reminder: false,
                          onTap: () => _openTaskEditor(task, _selected, lanes),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(Task task) {
    if (task.isCancelled) {
      return false;
    }
    if (_filter == 'high') {
      return task.priority == 'HIGH';
    }
    if (_filter != 'all') {
      return task.categoryId == _filter;
    }
    return true;
  }

  List<Task> _tasksOn(
    DateTime day,
    List<Task> tasks,
    Set<String> reminderTaskIds,
  ) {
    return tasks.where((task) {
      if (!_matchesFilter(task)) {
        return false;
      }
      if (_reminderOnly && !reminderTaskIds.contains(task.id)) {
        return false;
      }
      final start = task.plannedStartAt?.toLocal();
      final end = task.plannedEndAt?.toLocal();
      if (start == null && end == null) {
        return false;
      }
      final first = start == null
          ? DateTime(end!.year, end.month, end.day)
          : DateTime(start.year, start.month, start.day);
      final last = end == null
          ? DateTime(start!.year, start.month, start.day)
          : DateTime(end.year, end.month, end.day);
      final date = DateTime(day.year, day.month, day.day);
      return !date.isBefore(first) && !date.isAfter(last);
    }).toList();
  }

  List<TaskReminder> _remindersOn(DateTime day, List<TaskReminder> reminders) {
    return reminders.where((reminder) {
      final local = reminder.remindAt.toLocal();
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).toList();
  }

  String _taskTime(Task task) {
    if (task.plannedStartAt != null) {
      return _time(task.plannedStartAt!);
    }
    return 'Весь день';
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
      final day = _selected.day > lastDay ? lastDay : _selected.day;
      _selected = DateTime(_month.year, _month.month, day);
    });
  }

  Future<void> _openTaskEditor(
    Task? task,
    DateTime date,
    List<Lane> lanes,
  ) async {
    final existingReminder = task == null
        ? null
        : await ref.read(remindersRepositoryProvider).findForTask(task.id);
    if (!mounted || lanes.isEmpty) {
      return;
    }

    final result = await showTaskEditorDialog(
      context: context,
      lanes: lanes,
      task: task,
      reminderAt: existingReminder?.remindAt,
      initialDate: task == null ? date : null,
      allowReminder: task?.isCancelled != true,
    );
    if (result == null || !mounted) {
      return;
    }

    try {
      final outcome = await ref
          .read(taskEditorServiceProvider)
          .save(task: task, draft: result.draft, reminderAt: result.reminderAt);
      if (!mounted) {
        return;
      }
      if (!outcome.notificationsAllowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Сохранено, но уведомления запрещены в настройках системы',
            ),
          ),
        );
      }
      unawaited(ref.read(syncControllerProvider.notifier).sync());
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Некорректная задача'),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить задачу')),
        );
      }
    }
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.tasks,
    required this.reminders,
    required this.onTap,
    required this.onOpenTask,
  });

  final DateTime date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<Task> tasks;
  final List<TaskReminder> reminders;
  final VoidCallback onTap;
  final ValueChanged<Task> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = tasks.take(2).toList();
    return Opacity(
      opacity: inMonth ? 1 : 0.35,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: today
                          ? BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            )
                          : null,
                      child: Text(
                        '${date.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: today ? theme.colorScheme.onPrimary : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (reminders.isNotEmpty)
                      Icon(
                        Icons.notifications,
                        size: 8,
                        color: theme.colorScheme.tertiary,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                for (final task in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      onTap: () => onOpenTask(task),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _categoryColor(
                            theme,
                            task.categoryId,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 8.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (tasks.length > 2)
                  Text(
                    '+${tasks.length - 2}',
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 8.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _categoryColor(ThemeData theme, String? categoryId) {
    return switch (categoryId) {
      'work' => theme.colorScheme.primary,
      'family' => theme.colorScheme.error,
      _ => theme.colorScheme.secondary,
    };
  }
}

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({
    required this.time,
    required this.task,
    required this.reminder,
    required this.onTap,
  });

  final String time;
  final Task task;
  final bool reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: reminder
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.primary,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Text(time, style: theme.textTheme.labelSmall),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 5,
                    children: [
                      Text(
                        task.categoryName ?? 'Без категории',
                        style: theme.textTheme.labelSmall,
                      ),
                      if (reminder)
                        Text(
                          'Напоминание',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (task.isCancelled)
              Text(
                'Отменена',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
