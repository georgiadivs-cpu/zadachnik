import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/application/calendar_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/presentation/note_editor_page.dart';
import '../../sync/application/sync_controller.dart';
import '../../tasks/application/task_editor_service.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/domain/lane.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../data/search_repository.dart';
import '../domain/search_result.dart';
import 'highlighted_text.dart';

Future<void> openSearchPage(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => const SearchPage()));
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const _categories = [
    (id: 'work', label: 'Работа'),
    (id: 'personal', label: 'Личное'),
    (id: 'family', label: 'Семья'),
  ];

  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const [];
  SearchResultType? _type;
  String? _categoryId;
  bool _highPriority = false;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    final request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(searchRepositoryProvider)
          .search(
            query: query,
            filter: SearchFilter(
              type: _type,
              categoryId: _categoryId,
              highPriority: _highPriority,
            ),
          );
      if (!mounted || request != _requestId) {
        return;
      }
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object {
      if (!mounted || request != _requestId) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Не удалось выполнить поиск';
      });
    }
  }

  void _setType(SearchResultType? value) {
    setState(() => _type = value);
    if (_controller.text.trim().isNotEmpty) {
      unawaited(_runSearch());
    }
  }

  void _setCategory(String? value) {
    setState(() => _categoryId = value);
    if (_controller.text.trim().isNotEmpty) {
      unawaited(_runSearch());
    }
  }

  void _setHighPriority(bool value) {
    setState(() => _highPriority = value);
    if (_controller.text.trim().isNotEmpty) {
      unawaited(_runSearch());
    }
  }

  void _useSuggestion(String value) {
    _debounce?.cancel();
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() {});
    unawaited(_runSearch());
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final notes = _results
        .where((result) => result.type == SearchResultType.note)
        .toList();
    final tasks = _results
        .where((result) => result.type == SearchResultType.task)
        .toList();
    final lanes = ref.watch(lanesProvider).value ?? const <Lane>[];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Поиск'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                Icon(
                  Icons.offline_bolt_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text('Локально', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                key: const Key('searchField'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'Заметки, задачи, дорожки…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                            _runSearch();
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            _filters(),
            Expanded(child: _content(query, notes, tasks, lanes)),
          ],
        ),
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
          FilterChip(
            label: const Text('Все'),
            selected: _type == null,
            onSelected: (_) => _setType(null),
          ),
          FilterChip(
            label: const Text('Заметки'),
            selected: _type == SearchResultType.note,
            onSelected: (_) => _setType(SearchResultType.note),
          ),
          FilterChip(
            label: const Text('Задачи'),
            selected: _type == SearchResultType.task,
            onSelected: (_) => _setType(SearchResultType.task),
          ),
          FilterChip(
            label: const Text('Все категории'),
            selected: _categoryId == null,
            onSelected: (_) => _setCategory(null),
          ),
          for (final category in _categories)
            FilterChip(
              label: Text(category.label),
              selected: _categoryId == category.id,
              onSelected: (_) => _setCategory(category.id),
            ),
          FilterChip(
            label: const Text('Высокий приоритет'),
            selected: _highPriority,
            onSelected: _setHighPriority,
            avatar: const Icon(Icons.priority_high, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _content(
    String query,
    List<SearchResult> notes,
    List<SearchResult> tasks,
    List<Lane> lanes,
  ) {
    if (query.isEmpty) {
      return _emptyQuery();
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ничего не найдено.\n'
            'Попробуйте изменить запрос или снять фильтры.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          '${_results.length} результатов · локально',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (notes.isNotEmpty) ...[
          _groupTitle('Заметки', notes.length),
          for (final result in notes)
            _ResultCard(
              result: result,
              query: query,
              onTap: () => _openNote(result),
            ),
        ],
        if (tasks.isNotEmpty) ...[
          _groupTitle('Задачи', tasks.length),
          for (final result in tasks)
            _ResultCard(
              result: result,
              query: query,
              onTap: () => _openTask(result, lanes),
            ),
        ],
      ],
    );
  }

  Widget _emptyQuery() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 46, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Начните вводить запрос', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Поиск работает по локальной базе без сети: '
              'заголовки и текст заметок, названия и описания задач, '
              'дорожки, категории и напоминания.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final suggestion in ['план', 'Работа', 'встреча'])
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => _useSuggestion(suggestion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Text(
        '$title · $count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _openNote(SearchResult result) async {
    final note = await ref.read(notesRepositoryProvider).findById(result.id);
    if (!mounted) {
      return;
    }
    if (note == null) {
      _showMessage('Заметка не найдена');
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => NoteEditorPage(note: note)),
    );
    if (saved == true && mounted) {
      unawaited(ref.read(syncControllerProvider.notifier).sync());
    }
  }

  Future<void> _openTask(SearchResult result, List<Lane> lanes) async {
    final task = await ref.read(tasksRepositoryProvider).findById(result.id);
    if (!mounted) {
      return;
    }
    if (task == null) {
      _showMessage('Задача не найдена');
      return;
    }
    final reminder = await ref
        .read(remindersRepositoryProvider)
        .findForTask(task.id);
    if (!mounted) {
      return;
    }
    if (lanes.isEmpty) {
      _showMessage('Дорожки ещё не загружены');
      return;
    }
    final draft = await showTaskEditorDialog(
      context: context,
      lanes: lanes,
      task: task,
      reminderAt: reminder?.remindAt,
      allowReminder: !task.isCancelled,
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final outcome = await ref
          .read(taskEditorServiceProvider)
          .save(task: task, draft: draft.draft, reminderAt: draft.reminderAt);
      if (!mounted) {
        return;
      }
      if (!outcome.notificationsAllowed) {
        _showMessage('Уведомления запрещены в настройках системы');
      }
      unawaited(ref.read(syncControllerProvider.notifier).sync());
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.query,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTask = result.type == SearchResultType.task;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isTask
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isTask
                      ? Icons.check_box_outlined
                      : Icons.description_outlined,
                  size: 18,
                  color: isTask
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightedText(
                      text: result.title,
                      query: query,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (result.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      HighlightedText(
                        text: result.body,
                        query: query,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: [
                        _tag(
                          theme,
                          result.categoryName ?? 'Без категории',
                          theme.colorScheme.secondary,
                        ),
                        if (result.laneName != null)
                          _tag(
                            theme,
                            result.laneName!,
                            theme.colorScheme.primary,
                          ),
                        if (result.priority == 'HIGH')
                          _tag(theme, 'Высокий', theme.colorScheme.error),
                        if (result.reminderAt != null)
                          _tag(
                            theme,
                            '🔔 ${_formatTime(result.reminderAt!)}',
                            theme.colorScheme.tertiary,
                          ),
                        if (result.isCancelled)
                          _tag(theme, 'Отменена', theme.colorScheme.error),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
