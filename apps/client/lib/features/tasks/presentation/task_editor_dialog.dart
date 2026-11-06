import 'package:flutter/material.dart';

import '../domain/lane.dart';
import '../domain/task.dart';

Future<TaskDraft?> showTaskEditorDialog({
  required BuildContext context,
  required List<Lane> lanes,
  Task? task,
  String? initialLaneId,
}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (context) => TaskEditorDialog(
      lanes: lanes,
      task: task,
      initialLaneId: initialLaneId,
    ),
  );
}

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    super.key,
    required this.lanes,
    this.task,
    this.initialLaneId,
  });

  final List<Lane> lanes;
  final Task? task;
  final String? initialLaneId;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _laneId;
  String? _categoryId;
  String _priority = 'NORMAL';
  DateTime? _plannedStart;
  DateTime? _plannedEnd;
  DateTime? _actualStart;
  DateTime? _actualEnd;
  String? _error;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    _laneId =
        task?.laneId ??
        widget.initialLaneId ??
        (widget.lanes.isEmpty ? '' : widget.lanes.first.id);
    _categoryId = task?.categoryId;
    _priority = task?.priority ?? 'NORMAL';
    _plannedStart = task?.plannedStartAt;
    _plannedEnd = task?.plannedEndAt;
    _actualStart = task?.actualStartAt;
    _actualEnd = task?.actualEndAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название задачи');
      return;
    }
    if (_laneId.isEmpty) {
      setState(() => _error = 'Выберите дорожку');
      return;
    }
    if (_plannedStart != null &&
        _plannedEnd != null &&
        _plannedEnd!.isBefore(_plannedStart!)) {
      setState(() => _error = 'Плановое завершение раньше начала');
      return;
    }
    if (_actualStart != null &&
        _actualEnd != null &&
        _actualEnd!.isBefore(_actualStart!)) {
      setState(() => _error = 'Фактическое завершение раньше начала');
      return;
    }

    Navigator.of(context).pop(
      TaskDraft(
        title: title,
        description: _description.text,
        laneId: _laneId,
        categoryId: _categoryId,
        priority: _priority,
        plannedStartAt: _plannedStart?.toUtc(),
        plannedEndAt: _plannedEnd?.toUtc(),
        actualStartAt: _actualStart?.toUtc(),
        actualEndAt: _actualEnd?.toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Text(
                    _isNew ? 'Новая задача' : 'Задача',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('taskTitleField'),
                      controller: _title,
                      autofocus: true,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('taskDescriptionField'),
                      controller: _description,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Описание',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('taskLaneField'),
                      initialValue: _laneId.isEmpty ? null : _laneId,
                      decoration: const InputDecoration(labelText: 'Дорожка'),
                      items: [
                        for (final lane in widget.lanes)
                          DropdownMenuItem(
                            value: lane.id,
                            child: Text(lane.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _laneId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _categoryId ?? 'none',
                            decoration: const InputDecoration(
                              labelText: 'Категория',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'work',
                                child: Text('Работа'),
                              ),
                              DropdownMenuItem(
                                value: 'personal',
                                child: Text('Личное'),
                              ),
                              DropdownMenuItem(
                                value: 'family',
                                child: Text('Семья'),
                              ),
                              DropdownMenuItem(
                                value: 'none',
                                child: Text('Без категории'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () =>
                                  _categoryId = value == 'none' ? null : value,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _priority,
                            decoration: const InputDecoration(
                              labelText: 'Приоритет',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'LOW',
                                child: Text('Низкий'),
                              ),
                              DropdownMenuItem(
                                value: 'NORMAL',
                                child: Text('Обычный'),
                              ),
                              DropdownMenuItem(
                                value: 'HIGH',
                                child: Text('Высокий'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _priority = value ?? 'NORMAL'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DateField(
                      label: 'План: начало',
                      value: _plannedStart,
                      onPick: () => _pickDate(
                        current: _plannedStart,
                        onChanged: (value) =>
                            setState(() => _plannedStart = value),
                      ),
                      onClear: () => setState(() => _plannedStart = null),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'План: завершение',
                      value: _plannedEnd,
                      onPick: () => _pickDate(
                        current: _plannedEnd,
                        onChanged: (value) =>
                            setState(() => _plannedEnd = value),
                      ),
                      onClear: () => setState(() => _plannedEnd = null),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Факт: начало',
                      value: _actualStart,
                      onPick: () => _pickDate(
                        current: _actualStart,
                        onChanged: (value) =>
                            setState(() => _actualStart = value),
                      ),
                      onClear: () => setState(() => _actualStart = null),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      label: 'Факт: завершение',
                      value: _actualEnd,
                      onPick: () => _pickDate(
                        current: _actualEnd,
                        onChanged: (value) =>
                            setState(() => _actualEnd = value),
                      ),
                      onClear: () => setState(() => _actualEnd = null),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('taskSaveButton'),
                    onPressed: _save,
                    child: const Text('Сохранить'),
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final local = value?.toLocal();
    final text = local == null
        ? 'Не выбрано'
        : '${local.day.toString().padLeft(2, '0')}.'
              '${local.month.toString().padLeft(2, '0')}.${local.year}';
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        suffixIcon: value == null
            ? null
            : IconButton(
                tooltip: 'Очистить',
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 18),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: value == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
          TextButton(onPressed: onPick, child: const Text('Выбрать')),
        ],
      ),
    );
  }
}
