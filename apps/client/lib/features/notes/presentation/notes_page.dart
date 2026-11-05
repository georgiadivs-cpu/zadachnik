import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_controller.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';
import 'note_editor_page.dart';

class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final sync = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            tooltip: 'Синхронизировать',
            onPressed: sync.isRunning ? null : () => _sync(context, ref),
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
                  itemBuilder: (context, index) => _NoteCard(
                    note: items[index],
                    onTap: () => _openEditor(context, ref, items[index]),
                  ),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const Center(child: Text('Не удалось загрузить заметки')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Заметка'),
      ),
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    await ref.read(syncControllerProvider.notifier).sync();
    if (!context.mounted) {
      return;
    }
    final state = ref.read(syncControllerProvider);
    final message = switch (state.phase) {
      SyncPhase.success => 'Синхронизировано',
      SyncPhase.offline => 'Сервер недоступен, данные сохранены локально',
      SyncPhase.error => state.message ?? 'Ошибка синхронизации',
      _ => 'Синхронизация',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    Note? note,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => NoteEditorPage(note: note)),
    );
    if (saved == true && context.mounted) {
      await ref.read(syncControllerProvider.notifier).sync();
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
  const _NoteCard({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = switch (note.syncStatus) {
      'CONFLICT' => Icons.warning_amber_rounded,
      'ERROR' => Icons.error_outline,
      'PENDING' => Icons.cloud_upload_outlined,
      _ => Icons.cloud_done_outlined,
    };
    final statusColor = switch (note.syncStatus) {
      'CONFLICT' || 'ERROR' => theme.colorScheme.error,
      'PENDING' => theme.colorScheme.tertiary,
      _ => theme.colorScheme.primary,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.title, style: theme.textTheme.titleMedium),
              if (note.contentMarkdown.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.contentMarkdown,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    note.categoryName ?? 'Без категории',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Icon(statusIcon, size: 15, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(note.updatedAt),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
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
