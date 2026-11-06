import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/tasks_providers.dart';
import '../domain/lane.dart';

class LaneSettingsDialog extends ConsumerStatefulWidget {
  const LaneSettingsDialog({
    super.key,
    required this.lanes,
    required this.taskCounts,
  });

  final List<Lane> lanes;
  final Map<String, int> taskCounts;

  @override
  ConsumerState<LaneSettingsDialog> createState() => _LaneSettingsDialogState();
}

class _LaneSettingsDialogState extends ConsumerState<LaneSettingsDialog> {
  late final List<_LaneEdit> _lanes;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lanes = [
      for (final lane in widget.lanes)
        _LaneEdit(
          id: lane.id,
          name: lane.name,
          taskCount: widget.taskCounts[lane.id] ?? 0,
        ),
    ];
  }

  @override
  void dispose() {
    for (final lane in _lanes) {
      lane.controller.dispose();
    }
    super.dispose();
  }

  void _addLane() {
    if (_lanes.length >= 10) {
      setState(() => _error = 'Максимум 10 дорожек');
      return;
    }
    setState(() {
      _lanes.add(_LaneEdit(name: 'Новая дорожка'));
      _error = null;
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _lanes.length) {
      return;
    }
    setState(() {
      final item = _lanes.removeAt(index);
      _lanes.insert(target, item);
    });
  }

  void _remove(int index) {
    if (_lanes.length <= 3) {
      setState(() => _error = 'Минимум 3 дорожки');
      return;
    }
    if (_lanes[index].taskCount > 0) {
      setState(() => _error = 'Сначала перенесите задачи из этой дорожки');
      return;
    }
    setState(() {
      _lanes.removeAt(index).controller.dispose();
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(lanesRepositoryProvider).saveConfiguration([
        for (final lane in _lanes)
          LaneDraft(id: lane.id, name: lane.controller.text),
      ]);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message?.toString() ?? 'Не удалось сохранить дорожки';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Не удалось сохранить дорожки';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
              child: Row(
                children: [
                  Text('Дорожки', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'От 3 до 10 дорожек. Дорожка с задачами не удаляется, '
                'пока задачи не перенесены.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _lanes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final lane = _lanes[index];
                  return Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: Key('laneName$index'),
                          controller: lane.controller,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (lane.taskCount > 0)
                        Tooltip(
                          message: '${lane.taskCount} задач',
                          child: Chip(
                            label: Text('${lane.taskCount}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Выше',
                        onPressed: index == 0 ? null : () => _move(index, -1),
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Ниже',
                        onPressed: index == _lanes.length - 1
                            ? null
                            : () => _move(index, 1),
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        onPressed: lane.taskCount == 0 && _lanes.length > 3
                            ? () => _remove(index)
                            : null,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _lanes.length >= 10 ? null : _addLane,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('saveLanesButton'),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaneEdit {
  _LaneEdit({this.id, required String name, this.taskCount = 0})
    : controller = TextEditingController(text: name);

  final String? id;
  final int taskCount;
  final TextEditingController controller;
}
