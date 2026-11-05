import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notes_providers.dart';
import '../domain/note.dart';

typedef NoteDraft = ({String title, String content, String categoryId});

class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Поиск появится в следующем шаге'),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: SafeArea(
        child: notes.when(
          data: (items) => items.isEmpty
              ? const _EmptyNotes()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _NoteCard(note: items[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const Center(child: Text('Не удалось загрузить заметки')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNote(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Заметка'),
      ),
    );
  }

  Future<void> _createNote(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<NoteDraft>(
      context: context,
      builder: (context) => const _NewNoteDialog(),
    );
    if (draft == null) {
      return;
    }

    try {
      await ref
          .read(notesRepositoryProvider)
          .create(
            title: draft.title,
            contentMarkdown: draft.content,
            categoryId: draft.categoryId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заметка сохранена локально')),
        );
      }
    } on ArgumentError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Некорректная заметка'),
          ),
        );
      }
    }
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет заметок',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Создайте первую заметку. Она сохранится на устройстве '
              'и попадёт в очередь синхронизации.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.title, style: Theme.of(context).textTheme.titleMedium),
            if (note.contentMarkdown.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note.contentMarkdown,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  note.categoryName ?? 'Без категории',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  _formatDate(note.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month $hour:$minute';
  }
}

class _NewNoteDialog extends StatefulWidget {
  const _NewNoteDialog();

  @override
  State<_NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<_NewNoteDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String _categoryId = 'personal';
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите заголовок');
      return;
    }

    Navigator.of(context).pop<NoteDraft>((
      title: title,
      content: _content.text,
      categoryId: _categoryId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая заметка'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('noteTitle'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('noteContent'),
              controller: _content,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Markdown',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Категория'),
              items: const [
                DropdownMenuItem(value: 'work', child: Text('Работа')),
                DropdownMenuItem(value: 'personal', child: Text('Личное')),
                DropdownMenuItem(value: 'family', child: Text('Семья')),
              ],
              onChanged: (value) =>
                  setState(() => _categoryId = value ?? _categoryId),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('saveNote'),
          onPressed: _submit,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
