import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';

enum _EditorMode { edit, preview }

enum _ExitAction { save, discard }

/// Полноэкранный редактор заметки. Сохраняет через локальный outbox,
/// поэтому сеть не является условием сохранения.
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final Note? note;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage>
    with WidgetsBindingObserver {
  static const _autosaveDelay = Duration(milliseconds: 800);

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _categoryId;

  Note? _note;
  _EditorMode _mode = _EditorMode.edit;
  Timer? _autosaveTimer;
  bool _saving = false;
  bool _dirty = false;
  bool _savedAny = false;
  bool _dialogOpen = false;
  String? _error;
  DateTime? _savedAt;

  bool get _isNew => _note == null;

  bool get _canSave =>
      !_saving && _dirty && _titleController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.note;
    _titleController = TextEditingController(text: _note?.title ?? '');
    _contentController = TextEditingController(
      text: _note?.contentMarkdown ?? '',
    );
    _categoryId = _note?.categoryId ?? 'personal';
    _titleController.addListener(_handleEdit);
    _contentController.addListener(_handleEdit);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _titleController
      ..removeListener(_handleEdit)
      ..dispose();
    _contentController
      ..removeListener(_handleEdit)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_save(fromAutosave: true));
    }
  }

  void _handleEdit() {
    if (!mounted) {
      return;
    }
    setState(() {
      _dirty = true;
      _error = null;
    });
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      _autosaveDelay,
      () => unawaited(_save(fromAutosave: true)),
    );
  }

  Future<bool> _save({bool fromAutosave = false}) async {
    _autosaveTimer?.cancel();
    if (_saving) {
      return false;
    }

    final title = _titleController.text.trim();
    final content = _contentController.text;
    final categoryId = _categoryId;

    if (title.isEmpty) {
      if (!fromAutosave) {
        setState(() => _error = 'Введите заголовок заметки');
      }
      return false;
    }
    if (!_dirty && _note != null) {
      return true;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(notesRepositoryProvider);
      if (_note == null) {
        final id = await repository.create(
          title: title,
          contentMarkdown: content,
          categoryId: categoryId,
        );
        final created = await repository.findById(id);
        if (!mounted) {
          return false;
        }
        _note = created;
      } else {
        await repository.updateLocal(
          note: _note!,
          title: title,
          contentMarkdown: content,
          categoryId: categoryId,
        );
        final updated = await repository.findById(_note!.id);
        if (!mounted) {
          return false;
        }
        if (updated != null) {
          _note = updated;
        }
      }

      final unchanged =
          _titleController.text.trim() == title &&
          _contentController.text == content &&
          _categoryId == categoryId;
      if (!mounted) {
        return false;
      }

      setState(() {
        _saving = false;
        _dirty = !unchanged;
        _savedAny = true;
        _savedAt = DateTime.now().toUtc();
      });

      if (!unchanged) {
        _scheduleAutosave();
      }
      if (!fromAutosave) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Заметка сохранена')));
      }
      return true;
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = true;
          _error = error.message?.toString() ?? 'Некорректная заметка';
        });
      }
      return false;
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = true;
          _error = 'Не удалось сохранить заметку';
        });
      }
      return false;
    } finally {
      if (mounted && _saving) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _attemptPop() async {
    if (_dialogOpen) {
      return;
    }
    if (_saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дождитесь окончания сохранения')),
      );
      return;
    }
    if (!_dirty) {
      _close();
      return;
    }

    _autosaveTimer?.cancel();
    _dialogOpen = true;
    final action = await showDialog<_ExitAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Несохранённые изменения'),
        content: const Text(
          'Если выйти сейчас, последние изменения не попадут в локальную базу.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExitAction.discard),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Выйти без сохранения'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ExitAction.save),
            child: const Text('Сохранить и выйти'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) {
      return;
    }
    if (action == null) {
      if (_dirty) {
        _scheduleAutosave();
      }
      return;
    }

    if (action == _ExitAction.discard) {
      _autosaveTimer?.cancel();
      _dirty = false;
      _close();
      return;
    }

    final saved = await _save();
    if (saved && mounted) {
      _close();
    }
  }

  Future<void> _openAttachments() async {
    final note = _note;
    if (note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала сохраните заметку')),
      );
      return;
    }
    await showAttachmentSheet(
      context,
      ref,
      ownerType: AttachmentOwnerType.note,
      ownerId: note.id,
    );
  }

  void _close() {
    if (mounted) {
      Navigator.of(context).pop(_savedAny);
    }
  }

  void _changeCategory(String? value) {
    if (value == null || value == _categoryId) {
      return;
    }
    setState(() => _categoryId = value);
    _handleEdit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_save()),
      },
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(_attemptPop());
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('noteBackButton'),
              tooltip: 'Назад',
              onPressed: _attemptPop,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(_isNew ? 'Новая заметка' : 'Заметка'),
            actions: [
              IconButton(
                key: const Key('noteAttachmentsButton'),
                tooltip: 'Вложения',
                onPressed: _openAttachments,
                icon: const Icon(Icons.attach_file),
              ),
              IconButton(
                key: const Key('noteSaveButton'),
                tooltip: 'Сохранить',
                onPressed: _canSave ? () => unawaited(_save()) : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_error != null) _ErrorBanner(message: _error!),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _statusRow(theme),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('noteTitleField'),
                              controller: _titleController,
                              maxLength: 200,
                              textInputAction: TextInputAction.next,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Заголовок',
                                border: InputBorder.none,
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                DropdownButton<String>(
                                  key: const Key('noteCategoryField'),
                                  value: _categoryId,
                                  underline: const SizedBox.shrink(),
                                  borderRadius: BorderRadius.circular(10),
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
                                  ],
                                  onChanged: _changeCategory,
                                ),
                                SegmentedButton<_EditorMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: _EditorMode.edit,
                                      label: Text(
                                        'Редактор',
                                        key: Key('noteEditTab'),
                                      ),
                                      icon: Icon(Icons.edit_outlined, size: 16),
                                    ),
                                    ButtonSegment(
                                      value: _EditorMode.preview,
                                      label: Text(
                                        'Предпросмотр',
                                        key: Key('notePreviewTab'),
                                      ),
                                      icon: Icon(
                                        Icons.visibility_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                  selected: {_mode},
                                  showSelectedIcon: false,
                                  onSelectionChanged: (selection) =>
                                      setState(() => _mode = selection.first),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _mode == _EditorMode.edit
                                  ? _buildEditor(theme)
                                  : _buildPreview(theme),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _dirty || _saving
              ? _UnsavedBar(
                  saving: _saving,
                  onSave: _canSave ? () => unawaited(_save()) : null,
                )
              : null,
        ),
      ),
    );
  }

  Widget _statusRow(ThemeData theme) {
    final label = _saveLabel();
    final color = _dirty
        ? theme.colorScheme.tertiary
        : _saving
        ? theme.colorScheme.primary
        : theme.colorScheme.primary;

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              key: const Key('noteSaveState'),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ),
        _SyncBadge(note: _note),
        Text(
          '${_contentController.text.length} символов',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _saveLabel() {
    if (_saving) {
      return 'Сохранение…';
    }
    if (_dirty) {
      return 'Есть несохранённые изменения';
    }
    if (_savedAt != null) {
      final local = _savedAt!.toLocal();
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return 'Сохранено в $hour:$minute';
    }
    return _isNew ? 'Новая заметка' : 'Все изменения сохранены';
  }

  Widget _buildEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const Key('noteContentField'),
            controller: _contentController,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: '# Заголовок\n\nТекст заметки в Markdown…',
              alignLabelWithHint: true,
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Чек-листы редактируются как Markdown. '
          'Интерактивные задачи появятся вместе с TODO-доской.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final data = _contentController.text;
    if (data.trim().isEmpty) {
      return Center(
        child: Text(
          'Начните вводить Markdown — предпросмотр появится здесь.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: MarkdownBody(
          data: data,
          selectable: true,
          onTapLink: (text, href, title) {
            if (href == null) {
              return;
            }
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Ссылка: $href')));
          },
          // Не загружаем внешние изображения из заметки: это сетевой запрос
          // и потенциальная утечка данных без согласия пользователя.
          imageBuilder: (uri, title, alt) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    alt ?? title ?? uri.toString(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            h1: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            h2: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            h3: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            blockquote: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            blockquoteDecoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            blockquotePadding: const EdgeInsets.all(12),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            codeblockDecoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            codeblockPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.note});

  final Note? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = note?.syncStatus;
    final (label, color) = switch (status) {
      'CONFLICT' => ('Конфликт', theme.colorScheme.error),
      'ERROR' => ('Ошибка sync', theme.colorScheme.error),
      'PENDING' => ('Ожидает sync', theme.colorScheme.tertiary),
      'SYNCED' => ('Синхронизировано', theme.colorScheme.primary),
      _ => ('Локально', theme.colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsavedBar extends StatelessWidget {
  const _UnsavedBar({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            if (saving)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.cloud_upload_outlined,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                saving
                    ? 'Сохраняем изменения…'
                    : 'Есть несохранённые изменения',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
            TextButton(onPressed: onSave, child: const Text('Сохранить')),
          ],
        ),
      ),
    );
  }
}
