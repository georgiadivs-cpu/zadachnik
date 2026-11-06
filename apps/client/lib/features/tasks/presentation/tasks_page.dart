import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/application/calendar_providers.dart';
import '../../sync/application/sync_controller.dart';
import '../application/task_editor_service.dart';
import '../application/tasks_providers.dart';
import '../domain/lane.dart';
import '../domain/task.dart';
import 'lane_settings_dialog.dart';
import 'task_editor_dialog.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  String _filter = 'all';
  bool _showCancelled = false;

  @override
  Widget build(BuildContext context) {
    final lanes = ref.watch(lanesProvider);
    final tasks = ref.watch(tasksProvider);
    final reminders = ref.watch(remindersProvider);
    final sync = ref.watch(syncControllerProvider);
    final reminderTaskIds =
        reminders.value?.map((reminder) => reminder.taskId).toSet() ??
        const <String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Задачи'),
        actions: [
          IconButton(
            tooltip: 'Синхронизировать',
            onPressed: sync.isRunning
                ? null
                : () => _sync(context, ref, notify: true),
            icon: sync.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    sync.phase == SyncPhase.offline ||
                            sync.phase == SyncPhase.error
                        ? Icons.cloud_off
                        : Icons.cloud_done_outlined,
                  ),
          ),
          IconButton(
            key: const Key('laneSettingsButton'),
            tooltip: 'Настроить дорожки',
            onPressed: () => _openLaneSettings(lanes.value ?? const []),
            icon: const Icon(Icons.view_column_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: lanes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const Center(child: Text('Не удалось загрузить дорожки')),
          data: (lanesData) => tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) =>
                const Center(child: Text('Не удалось загрузить задачи')),
            data: (tasksData) =>
                _buildBoard(lanesData, tasksData, reminderTaskIds),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final lanesData = lanes.value ?? const [];
          if (lanesData.isNotEmpty) {
            _openTaskEditor(null, lanesData, laneId: lanesData.first.id);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Задача'),
      ),
    );
  }

  Widget _buildBoard(
    List<Lane> lanes,
    List<Task> tasks,
    Set<String> reminderTaskIds,
  ) {
    final visible = tasks.where(_matchesFilter).toList();
    final cancelled = tasks.where((task) => task.isCancelled).toList();
    final taskCounts = <String, int>{};
    for (final task in tasks) {
      taskCounts.update(task.laneId, (value) => value + 1, ifAbsent: () => 1);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip('all', 'Все'),
              _filterChip('work', 'Работа'),
              _filterChip('personal', 'Личное'),
              _filterChip('family', 'Семья'),
              _filterChip('high', 'Высокий приоритет'),
              FilterChip(
                label: const Text('Отменённые'),
                selected: _showCancelled,
                onSelected: (value) => setState(() => _showCancelled = value),
                avatar: const Icon(Icons.block, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: constraints.maxHeight - 24,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final lane in lanes)
                        _LaneColumn(
                          lane: lane,
                          tasks: visible
                              .where((task) => task.laneId == lane.id)
                              .toList(),
                          allTasks: visible,
                          allLanes: lanes,
                          reminderTaskIds: reminderTaskIds,
                          onOpenTask: (task) => _openTaskEditor(task, lanes),
                          onMoveTask: (task, laneId) => _moveTask(task, laneId),
                          onCancelTask: (task) => _setCancelled(task, true),
                          onRestoreTask: (task) => _setCancelled(task, false),
                          onAddTask: () =>
                              _openTaskEditor(null, lanes, laneId: lane.id),
                          onLaneSettings: () =>
                              _openLaneSettings(lanes, taskCounts: taskCounts),
                        ),
                      if (_showCancelled)
                        _CancelledColumn(
                          tasks: cancelled,
                          onOpenTask: (task) => _openTaskEditor(task, lanes),
                          onRestoreTask: (task) => _setCancelled(task, false),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

  Future<void> _openTaskEditor(
    Task? task,
    List<Lane> lanes, {
    String? laneId,
  }) async {
    final existingReminder = task == null
        ? null
        : await ref.read(remindersRepositoryProvider).findForTask(task.id);
    if (!mounted) {
      return;
    }
    final result = await showTaskEditorDialog(
      context: context,
      lanes: lanes,
      task: task,
      initialLaneId: laneId,
      reminderAt: existingReminder?.remindAt,
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
        _showMessage(
          'Задача сохранена, но уведомления запрещены в настройках системы',
        );
      }
      unawaited(_sync(context, ref, notify: false));
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(error.message?.toString() ?? 'Некорректная задача');
      }
    } on Object {
      if (mounted) {
        _showMessage('Не удалось сохранить задачу');
      }
    }
  }

  Future<void> _moveTask(Task task, String laneId) async {
    try {
      await ref.read(tasksRepositoryProvider).moveToLane(task, laneId);
      if (mounted) {
        unawaited(_sync(context, ref, notify: false));
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(error.message?.toString() ?? 'Не удалось переместить');
      }
    }
  }

  Future<void> _setCancelled(Task task, bool cancelled) async {
    try {
      await ref.read(tasksRepositoryProvider).setCancelled(task, cancelled);
      if (cancelled) {
        await ref.read(reminderCoordinatorProvider).cancelForTask(task.id);
      }
      if (mounted) {
        _showMessage(cancelled ? 'Задача отменена' : 'Задача возвращена');
        unawaited(_sync(context, ref, notify: false));
      }
    } on Object {
      if (mounted) {
        _showMessage('Не удалось изменить состояние задачи');
      }
    }
  }

  Future<void> _openLaneSettings(
    List<Lane> lanes, {
    Map<String, int>? taskCounts,
  }) async {
    if (lanes.isEmpty) {
      return;
    }
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final counts = taskCounts ?? <String, int>{};
    if (taskCounts == null) {
      for (final task in tasks) {
        counts.update(task.laneId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          LaneSettingsDialog(lanes: lanes, taskCounts: counts),
    );
    if (saved == true && mounted) {
      unawaited(_sync(context, ref, notify: false));
    }
  }

  Future<void> _sync(
    BuildContext context,
    WidgetRef ref, {
    required bool notify,
  }) async {
    await ref.read(syncControllerProvider.notifier).sync();
    if (!notify || !context.mounted) {
      return;
    }
    final state = ref.read(syncControllerProvider);
    final message = switch (state.phase) {
      SyncPhase.success => 'Синхронизировано',
      SyncPhase.offline => 'Сервер недоступен, задачи сохранены локально',
      SyncPhase.error => state.message ?? 'Ошибка синхронизации',
      _ => 'Синхронизация',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lane,
    required this.tasks,
    required this.allTasks,
    required this.allLanes,
    required this.reminderTaskIds,
    required this.onOpenTask,
    required this.onMoveTask,
    required this.onCancelTask,
    required this.onRestoreTask,
    required this.onAddTask,
    required this.onLaneSettings,
  });

  final Lane lane;
  final List<Task> tasks;
  final List<Task> allTasks;
  final List<Lane> allLanes;
  final Set<String> reminderTaskIds;
  final ValueChanged<Task> onOpenTask;
  final void Function(Task task, String laneId) onMoveTask;
  final ValueChanged<Task> onCancelTask;
  final ValueChanged<Task> onRestoreTask;
  final VoidCallback onAddTask;
  final VoidCallback onLaneSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final task = allTasks
            .where((item) => item.id == details.data)
            .firstOrNull;
        if (task != null) {
          onMoveTask(task, lane.id);
        }
      },
      builder: (context, candidate, rejected) {
        return Container(
          width: 286,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: candidate.isNotEmpty
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lane.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('${tasks.length}', style: theme.textTheme.bodySmall),
                  IconButton(
                    tooltip: 'Настроить дорожки',
                    onPressed: onLaneSettings,
                    icon: const Icon(Icons.more_horiz, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          'Перетащите задачу сюда',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return _DraggableTaskCard(
                            task: task,
                            allLanes: allLanes,
                            hasReminder: reminderTaskIds.contains(task.id),
                            onOpen: () => onOpenTask(task),
                            onMove: (laneId) => onMoveTask(task, laneId),
                            onCancel: () => onCancelTask(task),
                            onRestore: () => onRestoreTask(task),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onAddTask,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Задача'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CancelledColumn extends StatelessWidget {
  const _CancelledColumn({
    required this.tasks,
    required this.onOpenTask,
    required this.onRestoreTask,
  });

  final List<Task> tasks;
  final ValueChanged<Task> onOpenTask;
  final ValueChanged<Task> onRestoreTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 286,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.block, size: 17, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Отменённые',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              Text('${tasks.length}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      'Нет отменённых задач',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _TaskCard(
                        task: task,
                        allLanes: const [],
                        hasReminder: false,
                        onOpen: () => onOpenTask(task),
                        onMove: (_) {},
                        onCancel: null,
                        onRestore: () => onRestoreTask(task),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraggableTaskCard extends StatelessWidget {
  const _DraggableTaskCard({
    required this.task,
    required this.allLanes,
    required this.hasReminder,
    required this.onOpen,
    required this.onMove,
    required this.onCancel,
    required this.onRestore,
  });

  final Task task;
  final List<Lane> allLanes;
  final bool hasReminder;
  final VoidCallback onOpen;
  final ValueChanged<String> onMove;
  final VoidCallback onCancel;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final card = _TaskCard(
      task: task,
      allLanes: allLanes,
      hasReminder: hasReminder,
      onOpen: onOpen,
      onMove: onMove,
      onCancel: onCancel,
      onRestore: onRestore,
    );
    if (task.isCancelled) {
      return card;
    }
    return LongPressDraggable<String>(
      data: task.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 266, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.allLanes,
    required this.hasReminder,
    required this.onOpen,
    required this.onMove,
    required this.onCancel,
    required this.onRestore,
  });

  final Task task;
  final List<Lane> allLanes;
  final bool hasReminder;
  final VoidCallback onOpen;
  final ValueChanged<String> onMove;
  final VoidCallback? onCancel;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = switch (task.syncStatus) {
      'CONFLICT' => Icons.warning_amber_rounded,
      'ERROR' => Icons.error_outline,
      'PENDING' => Icons.cloud_upload_outlined,
      _ => Icons.cloud_done_outlined,
    };
    final statusColor = switch (task.syncStatus) {
      'CONFLICT' || 'ERROR' => theme.colorScheme.error,
      'PENDING' => theme.colorScheme.tertiary,
      _ => theme.colorScheme.primary,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (value) {
                      if (value == 'edit') {
                        onOpen();
                      } else if (value == 'cancel') {
                        onCancel?.call();
                      } else if (value == 'restore') {
                        onRestore?.call();
                      } else if (value.startsWith('move:')) {
                        onMove(value.substring(5));
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Открыть'),
                      ),
                      if (!task.isCancelled)
                        for (final lane in allLanes)
                          if (lane.id != task.laneId)
                            PopupMenuItem(
                              value: 'move:${lane.id}',
                              child: Text('Переместить: ${lane.name}'),
                            ),
                      if (!task.isCancelled)
                        PopupMenuItem(
                          value: 'cancel',
                          child: Text(
                            'Отменить задачу',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (task.isCancelled)
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('Вернуть в работу'),
                        ),
                    ],
                  ),
                ],
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  _Tag(
                    text: task.categoryName ?? 'Без категории',
                    color: theme.colorScheme.secondary,
                  ),
                  if (task.priority == 'HIGH')
                    _Tag(text: 'Высокий', color: theme.colorScheme.error),
                  if (hasReminder)
                    _Tag(
                      text: 'Напоминание',
                      color: theme.colorScheme.tertiary,
                    ),
                  if (task.isCancelled)
                    _Tag(text: 'Отменена', color: theme.colorScheme.error),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _datesLabel(),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _datesLabel() {
    final planned = _range(task.plannedStartAt, task.plannedEndAt);
    if (planned != null) {
      return 'План: $planned';
    }
    final actual = _range(task.actualStartAt, task.actualEndAt);
    return actual == null ? 'Даты не заданы' : 'Факт: $actual';
  }

  String? _range(DateTime? start, DateTime? end) {
    if (start == null && end == null) {
      return null;
    }
    String format(DateTime? value) {
      if (value == null) {
        return '…';
      }
      final local = value.toLocal();
      return '${local.day.toString().padLeft(2, '0')}.'
          '${local.month.toString().padLeft(2, '0')}';
    }

    return '${format(start)} — ${format(end)}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
}
