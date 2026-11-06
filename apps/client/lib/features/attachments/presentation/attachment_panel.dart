import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_controller.dart';
import '../application/attachments_providers.dart';
import '../domain/attachment.dart';

Future<void> showAttachmentSheet(
  BuildContext context,
  WidgetRef ref, {
  required AttachmentOwnerType ownerType,
  required String ownerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        AttachmentPanel(ownerType: ownerType, ownerId: ownerId),
  );
}

class AttachmentPanel extends ConsumerWidget {
  const AttachmentPanel({
    super.key,
    required this.ownerType,
    required this.ownerId,
  });

  final AttachmentOwnerType ownerType;
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = (type: ownerType, id: ownerId);
    final attachments = ref.watch(attachmentsProvider(owner));
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Вложения',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                key: const Key('addAttachmentButton'),
                onPressed: () => _pickFile(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Выбрать файл'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'До 25 МБ. Изображения, PDF, текст/Markdown, аудио. '
              'Недогруженный файл не считается готовым.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: attachments.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
              error: (error, stackTrace) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Не удалось загрузить вложения'),
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 38,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Пока нет вложений',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Выберите файл на устройстве. '
                            'Метаданные синхронизируются, файл передаётся отдельно.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _AttachmentRow(
                        attachment: items[index],
                        onDelete: () => _delete(context, ref, items[index]),
                        onRetry: () => ref
                            .read(attachmentCoordinatorProvider)
                            .retry(items[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    try {
      const group = XTypeGroup(
        label: 'Вложения',
        extensions: AttachmentRules.extensions,
      );
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      final attachment = await ref
          .read(attachmentCoordinatorProvider)
          .addFile(ownerType: ownerType, ownerId: ownerId, file: file);
      if (!context.mounted) {
        return;
      }
      unawaited(ref.read(attachmentCoordinatorProvider).reconcile());
      unawaited(ref.read(syncControllerProvider.notifier).sync());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${attachment.fileName} добавлен')),
      );
    } on ArgumentError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Файл не разрешён'),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось добавить файл')),
        );
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Attachment attachment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить вложение?'),
        content: Text(
          'Файл «${attachment.fileName}» будет удалён '
          '${attachment.isUploaded ? 'с сервера и устройства' : 'с устройства'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await ref.read(attachmentCoordinatorProvider).deleteAttachment(attachment);
    unawaited(ref.read(syncControllerProvider.notifier).sync());
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.onDelete,
    required this.onRetry,
  });

  final Attachment attachment;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = attachment.mimeType.startsWith('image/');
    final canShowImage =
        image &&
        attachment.localPath != null &&
        File(attachment.localPath!).existsSync();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(
          color: attachment.uploadStatus == 'ERROR'
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            clipBehavior: Clip.antiAlias,
            child: canShowImage
                ? Image.file(File(attachment.localPath!), fit: BoxFit.cover)
                : Icon(
                    _icon(attachment.mimeType),
                    color: theme.colorScheme.primary,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      AttachmentRules.formatSize(attachment.sizeBytes),
                      style: theme.textTheme.labelSmall,
                    ),
                    _statusTag(theme),
                  ],
                ),
                if (attachment.uploadStatus == 'ERROR' &&
                    attachment.errorMessage != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    attachment.errorMessage!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (attachment.uploadStatus == 'ERROR')
            IconButton(
              tooltip: 'Повторить',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTag(ThemeData theme) {
    final (label, color) = switch (attachment.uploadStatus) {
      'READY' => ('Готово', theme.colorScheme.primary),
      'PENDING' ||
      'UPLOADING' => ('Ожидает загрузки', theme.colorScheme.tertiary),
      'REMOTE' => ('Загружается', theme.colorScheme.primary),
      'ERROR' => ('Ошибка', theme.colorScheme.error),
      'DELETE_PENDING' => ('Удаляется', theme.colorScheme.tertiary),
      _ => ('Файл', theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  static IconData _icon(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return Icons.image_outlined;
    }
    if (mimeType == 'application/pdf') {
      return Icons.picture_as_pdf_outlined;
    }
    if (mimeType.startsWith('audio/')) {
      return Icons.audiotrack_outlined;
    }
    return Icons.description_outlined;
  }
}
