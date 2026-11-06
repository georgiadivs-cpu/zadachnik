import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/application/calendar_providers.dart';
import '../../sync/application/sync_controller.dart';
import '../../tasks/application/task_editor_service.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/domain/lane.dart';
import '../../tasks/domain/task.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../domain/gantt_timeline.dart';

class GanttPage extends ConsumerStatefulWidget {
  const GanttPage({super.key, this.initialDate, this.today});

  final DateTime? initialDate;
  final DateTime? today;

  @override
  ConsumerState<GanttPage> createState() => _GanttPageState();
}

class _GanttPageState extends ConsumerState<GanttPage> {
  static const _labelWidth = 230.0;
  static const _months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];

  late DateTime _anchor;
  late DateTime _today;
  GanttScale _scale = GanttScale.week;
  String _filter = 'all';
  bool _showActual = true;

  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? DateTime.now();
    _anchor = widget.initialDate ?? _today;
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final lanes = ref.watch(lanesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Гант')),
      body: SafeArea(
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const Center(child: Text('Не удалось загрузить задачи')),
          data: (tasksData) => lanes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) =>
                const Center(child: Text('Не удалось загрузить дорожки')),
            data: (lanesData) => _buildContent(tasksData, lanesData),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<Task> tasks, List<Lane> lanes) {
    final laneNames = {for (final lane in lanes) lane.id: lane.name};
    final visible =
        tasks
            .where((task) => !task.isCancelled && ganttTaskHasDates(task))
            .where(_matchesFilter)
            .toList()
          ..sort((a, b) {
            final aStart = a.plannedStartAt ?? a.actualStartAt;
            final bStart = b.plannedStartAt ?? b.actualStartAt;
            if (aStart == null && bStart == null) {
              return a.title.compareTo(b.title);
            }
            if (aStart == null) {
              return 1;
            }
            if (bStart == null) {
              return -1;
            }
            return aStart.compareTo(bStart);
          });

    final range = buildGanttRange(_anchor, _scale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(range),
        _filters(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: visible.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Нет задач с датами для выбранного фильтра.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _timeline(range, visible, laneNames, lanes),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls(GanttRange range) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _rangeLabel(range),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Назад',
            onPressed: () =>
                setState(() => _anchor = moveGanttAnchor(_anchor, _scale, -1)),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: () => setState(() => _anchor = _today),
            child: const Text('Сегодня'),
          ),
          IconButton(
            tooltip: 'Вперёд',
            onPressed: () =>
                setState(() => _anchor = moveGanttAnchor(_anchor, _scale, 1)),
            icon: const Icon(Icons.chevron_right),
          ),
          SegmentedButton<GanttScale>(
            key: const Key('ganttScale'),
            segments: const [
              ButtonSegment(
                value: GanttScale.day,
                label: Text('День', key: Key('ganttScaleDay')),
              ),
              ButtonSegment(
                value: GanttScale.week,
                label: Text('Неделя', key: Key('ganttScaleWeek')),
              ),
              ButtonSegment(
                value: GanttScale.month,
                label: Text('Месяц', key: Key('ganttScaleMonth')),
              ),
            ],
            selected: {_scale},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _scale = selection.first),
          ),
          _legend(theme),
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
          _filterChip('all', 'Все задачи'),
          _filterChip('work', 'Работа'),
          _filterChip('personal', 'Личное'),
          _filterChip('family', 'Семья'),
          _filterChip('high', 'Высокий приоритет'),
          FilterChip(
            key: const Key('ganttActualToggle'),
            label: const Text('Показать фактические'),
            selected: _showActual,
            onSelected: (value) => setState(() => _showActual = value),
            avatar: const Icon(Icons.timeline, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      key: Key('ganttFilter-$value'),
      label: Text(label),
      selected: _filter == value,
      onSelected: (selected) =>
          setState(() => _filter = selected ? value : 'all'),
    );
  }

  Widget _legend(ThemeData theme) {
    return Wrap(
      spacing: 10,
      children: [
        _legendItem(theme.colorScheme.primary, 'план'),
        _legendItem(theme.colorScheme.secondary, 'факт'),
        _legendItem(theme.colorScheme.error, 'просрочено'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _timeline(
    GanttRange range,
    List<Task> tasks,
    Map<String, String> laneNames,
    List<Lane> lanes,
  ) {
    final cellWidth = switch (_scale) {
      GanttScale.day => 54.0,
      GanttScale.week => 84.0,
      GanttScale.month => 76.0,
    };
    final timelineWidth = range.cells * cellWidth;
    final totalWidth = _labelWidth + timelineWidth;

    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalController,
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.depth == 1,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(range, cellWidth),
                  for (final task in tasks)
                    _row(task, range, cellWidth, laneNames[task.laneId], lanes),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(GanttRange range, double cellWidth) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                'Задача',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          for (var index = 0; index < range.cells; index += 1)
            _headerCell(range, index, cellWidth),
        ],
      ),
    );
  }

  Widget _headerCell(GanttRange range, int index, double cellWidth) {
    final theme = Theme.of(context);
    final date = _cellDate(range, index);
    final containsToday = _cellContains(range, index, _today);
    return Container(
      width: cellWidth,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      decoration: BoxDecoration(
        color: containsToday
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        _cellLabel(date),
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: containsToday ? theme.colorScheme.primary : null,
          fontWeight: containsToday ? FontWeight.w700 : null,
        ),
      ),
    );
  }

  Widget _row(
    Task task,
    GanttRange range,
    double cellWidth,
    String? laneName,
    List<Lane> lanes,
  ) {
    final theme = Theme.of(context);
    final overdue = isGanttOverdue(task, _today);
    final plan = layoutGanttBar(
      start: task.plannedStartAt,
      end: task.plannedEndAt,
      range: range,
    );
    final actualEnd =
        task.actualEndAt ?? (task.actualStartAt == null ? null : _today);
    final actual = layoutGanttBar(
      start: task.actualStartAt,
      end: actualEnd,
      range: range,
    );

    return InkWell(
      key: Key('ganttRow-${task.id}'),
      onTap: () => _openTaskEditor(task, lanes),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: [
                        _smallTag(
                          task.categoryName ?? 'Без категории',
                          theme.colorScheme.secondary,
                        ),
                        if (laneName != null)
                          _smallTag(laneName, theme.colorScheme.primary),
                        if (task.priority == 'HIGH')
                          _smallTag('Высокий', theme.colorScheme.error),
                        if (overdue)
                          _smallTag('Просрочено', theme.colorScheme.error),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: range.cells * cellWidth,
              height: 62,
              child: Stack(
                children: [
                  Row(
                    children: [
                      for (var index = 0; index < range.cells; index += 1)
                        Container(
                          width: cellWidth,
                          decoration: BoxDecoration(
                            color: _cellContains(range, index, _today)
                                ? theme.colorScheme.primaryContainer.withValues(
                                    alpha: 0.25,
                                  )
                                : null,
                            border: Border(
                              left: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (plan != null)
                    Positioned(
                      key: Key('ganttPlan-${task.id}'),
                      left: plan.left * range.cells * cellWidth,
                      top: 16,
                      width: (plan.width * range.cells * cellWidth).clamp(
                        3,
                        double.infinity,
                      ),
                      height: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: overdue
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  if (_showActual && actual != null)
                    Positioned(
                      key: Key('ganttActual-${task.id}'),
                      left: actual.left * range.cells * cellWidth,
                      top: 34,
                      width: (actual.width * range.cells * cellWidth).clamp(
                        3,
                        double.infinity,
                      ),
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  bool _matchesFilter(Task task) {
    if (_filter == 'high') {
      return task.priority == 'HIGH';
    }
    if (_filter != 'all') {
      return task.categoryId == _filter;
    }
    return true;
  }

  String _rangeLabel(GanttRange range) {
    final end = range.end.subtract(const Duration(days: 1));
    if (_scale == GanttScale.month) {
      return '${_months[range.start.month - 1]} ${range.start.year} — '
          '${_months[end.month - 1]} ${end.year}';
    }
    return '${range.start.day} ${_months[range.start.month - 1]} — '
        '${end.day} ${_months[end.month - 1]}';
  }

  DateTime _cellDate(GanttRange range, int index) {
    if (_scale == GanttScale.day) {
      return range.start.add(Duration(days: index));
    }
    if (_scale == GanttScale.week) {
      return range.start.add(Duration(days: index * 7));
    }
    return DateTime(range.start.year, range.start.month + index, 1);
  }

  bool _cellContains(GanttRange range, int index, DateTime date) {
    final start = _cellDate(range, index);
    final end = _scale == GanttScale.day
        ? start
        : _scale == GanttScale.week
        ? start.add(const Duration(days: 6))
        : DateTime(start.year, start.month + 1, 0);
    final value = DateTime(date.year, date.month, date.day);
    return !value.isBefore(start) && !value.isAfter(end);
  }

  String _cellLabel(DateTime date) {
    if (_scale == GanttScale.month) {
      return '${_months[date.month - 1]} ${date.year.toString().substring(2)}';
    }
    return '${date.day} ${_months[date.month - 1]}';
  }

  Future<void> _openTaskEditor(Task task, List<Lane> lanes) async {
    final existingReminder = await ref
        .read(remindersRepositoryProvider)
        .findForTask(task.id);
    if (!mounted || lanes.isEmpty) {
      return;
    }
    final result = await showTaskEditorDialog(
      context: context,
      lanes: lanes,
      task: task,
      reminderAt: existingReminder?.remindAt,
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
            content: Text('Уведомления запрещены в настройках системы'),
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
