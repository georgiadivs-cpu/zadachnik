import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/backup_providers.dart';
import '../domain/backup_models.dart';
import 'backup_status_bar.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(backupControllerProvider.notifier).initialize();
      }
    });
  }

  Future<void> _start() async {
    final error = await ref
        .read(backupControllerProvider.notifier)
        .startBackup();
    if (!mounted) {
      return;
    }
    if (error != null) {
      _notify(error);
      return;
    }
    _notify('Копирование запущено на сервере');
    unawaited(_pollUntilDone());
  }

  Future<void> _pollUntilDone() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      for (var attempt = 0; attempt < 300; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) {
          return;
        }
        await ref.read(backupControllerProvider.notifier).refresh(silent: true);
        final running =
            ref.read(backupControllerProvider).status?.running ?? false;
        if (!running) {
          final state = ref.read(backupControllerProvider);
          if (state.status?.lastError != null) {
            _notify(state.status!.lastError!);
          } else {
            _notify('Резервная копия создана и проверена');
          }
          return;
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _verify(BackupArchiveView archive) async {
    final error = await ref
        .read(backupControllerProvider.notifier)
        .verifyArchive(archive.id);
    if (!mounted) {
      return;
    }
    _notify(error ?? 'Проверка копии завершена');
  }

  Future<void> _snapshot() async {
    final error = await ref
        .read(backupControllerProvider.notifier)
        .uploadDeviceSnapshot();
    if (!mounted) {
      return;
    }
    _notify(error ?? 'Снимок устройства загружен и зашифрован');
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupControllerProvider);
    final status = state.status;
    final session = ref.watch(authControllerProvider).session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Резервные копии'),
        actions: [
          IconButton(
            key: const Key('backupRefreshButton'),
            tooltip: 'Обновить',
            onPressed: state.loading
                ? null
                : () => ref
                      .read(backupControllerProvider.notifier)
                      .refresh(showLoading: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(backupControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            if (state.offline)
              const _Banner(
                icon: Icons.cloud_off,
                text:
                    'Нет связи с сервером. Показан последний известный статус; '
                    'создание копии недоступно.',
                tone: _BannerTone.warning,
              ),
            if (state.error != null)
              _Banner(
                icon: Icons.error_outline,
                text: state.error!,
                tone: _BannerTone.error,
              ),
            if (status == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (!status.configured)
                _Banner(
                  icon: Icons.settings_ethernet,
                  text:
                      status.configError ??
                      'Резервное копирование не настроено на сервере.',
                  tone: _BannerTone.error,
                ),
              _HeroCard(
                status: status,
                busy: state.busy,
                canStart: status.configured && !status.running,
                onStart: _start,
                onVerify: status.latestArchive == null
                    ? null
                    : () => _verify(status.latestArchive!),
                onSnapshot: _snapshot,
                currentDeviceId: session?.deviceId,
              ),
              const SizedBox(height: 12),
              _DeviceCard(
                status: status,
                currentDeviceId: session?.deviceId,
                busy: state.busy,
                onSnapshot: _snapshot,
              ),
              const SizedBox(height: 12),
              _HistoryCard(status: status, busy: state.busy, onVerify: _verify),
              const SizedBox(height: 12),
              _RetentionCard(status: status),
              const SizedBox(height: 12),
              const _RestoreCard(),
              const SizedBox(height: 12),
              const _EncryptionCard(),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.status,
    required this.busy,
    required this.canStart,
    required this.onStart,
    required this.onVerify,
    required this.onSnapshot,
    required this.currentDeviceId,
  });

  final BackupStatusSnapshot status;
  final bool busy;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback? onVerify;
  final VoidCallback onSnapshot;
  final String? currentDeviceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verified = status.latestArchive?.verified == true;
    final last = status.lastVerifiedAt;
    final title = status.running
        ? status.operation == 'VERIFY'
              ? 'Проверяю резервную копию'
              : 'Создаю резервную копию'
        : verified
        ? 'Последняя копия проверена'
        : 'Нет проверенной копии';
    final subtitle = status.running
        ? 'Сервер выполняет операцию. Экран можно закрыть — процесс продолжится.'
        : verified
        ? '${_formatDateTime(last)} · PostgreSQL, вложения и снимки устройств.'
        : 'Создайте копию и проверьте её, чтобы защитить данные.';
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: verified
                      ? scheme.primaryContainer
                      : scheme.tertiaryContainer,
                  child: Icon(
                    verified ? Icons.verified_user : Icons.backup_outlined,
                    color: verified
                        ? scheme.onPrimaryContainer
                        : scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (status.running) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (status.latestArchive != null && !status.running) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(
                    icon: Icons.schedule,
                    label: _relative(status.lastSuccessAt),
                  ),
                  _Chip(
                    icon: Icons.check_circle_outline,
                    label: verified
                        ? 'проверено ${_relative(last)}'
                        : 'не проверено',
                  ),
                  _Chip(
                    icon: Icons.data_object,
                    label: formatBytes(status.latestArchive!.sizeBytes),
                  ),
                  _Chip(
                    icon: Icons.storage,
                    label:
                        '${status.latestArchive!.counts['notes'] ?? 0} заметок',
                  ),
                ],
              ),
            ],
            if (status.lastError != null && !status.running) ...[
              const SizedBox(height: 12),
              _Banner(
                icon: Icons.error_outline,
                text: status.lastError!,
                tone: _BannerTone.error,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('backupStartButton'),
                  onPressed: busy || !canStart ? null : onStart,
                  icon: status.running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup),
                  label: const Text('Создать копию'),
                ),
                OutlinedButton.icon(
                  key: const Key('backupVerifyButton'),
                  onPressed: busy || status.running ? null : onVerify,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Проверить'),
                ),
                OutlinedButton.icon(
                  key: const Key('backupSnapshotButton'),
                  onPressed: busy || status.running ? null : onSnapshot,
                  icon: const Icon(Icons.phone_iphone),
                  label: const Text('Снимок устройства'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Текущее устройство: ${_deviceName(currentDeviceId)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.status,
    required this.currentDeviceId,
    required this.busy,
    required this.onSnapshot,
  });

  final BackupStatusSnapshot status;
  final String? currentDeviceId;
  final bool busy;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Снимки устройств',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  'последние ${status.retentionDeviceSnapshots}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'SQLite и журнал AI. Токены и secure storage не копируются; '
              'вложения уже хранятся на сервере.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (status.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Снимков пока нет.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final device in status.devices)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    device.deviceId == currentDeviceId
                        ? Icons.computer
                        : Icons.smartphone,
                  ),
                  title: Text(
                    device.deviceId == currentDeviceId
                        ? 'Это устройство'
                        : 'Устройство ${device.deviceId.substring(0, 8)}…',
                  ),
                  subtitle: Text(
                    '${_formatDateTime(device.latest.createdAt)} · '
                    'схема v${device.latest.schemaVersion} · '
                    '${formatBytes(device.latest.sizeBytes)}',
                  ),
                  trailing: Text(
                    '${device.snapshotCount}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const Key('backupUploadSnapshotButton'),
              onPressed: busy || status.running ? null : onSnapshot,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Отправить снимок этого устройства'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.status,
    required this.busy,
    required this.onVerify,
  });

  final BackupStatusSnapshot status;
  final bool busy;
  final ValueChanged<BackupArchiveView> onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('История', style: theme.textTheme.titleSmall),
                ),
                Text(
                  '${status.archives.length} копий',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (status.archives.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Копий пока нет.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final archive in status.archives.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    archive.verified ? Icons.verified : Icons.shield_outlined,
                    color: archive.verified
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                  ),
                  title: Text(_formatDateTime(archive.createdAt)),
                  subtitle: Text(
                    '${formatBytes(archive.sizeBytes)} · '
                    '${archive.counts['notes'] ?? 0} заметок · '
                    '${archive.counts['attachments'] ?? 0} вложений',
                  ),
                  trailing: archive.verified
                      ? Text(
                          'проверено',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : TextButton(
                          onPressed: busy || status.running
                              ? null
                              : () => onVerify(archive),
                          child: const Text('Проверить'),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RetentionCard extends StatelessWidget {
  const _RetentionCard({required this.status});

  final BackupStatusSnapshot status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Диск и хранение', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Свободно',
                    value: formatBytes(status.diskFreeBytes),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Всего',
                    value: formatBytes(status.diskTotalBytes),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Занято копиями',
                    value: formatBytes(
                      status.archives.fold(
                        0,
                        (sum, archive) => sum + archive.sizeBytes,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.history,
                  label: '${status.retentionRecent} последних',
                ),
                _Chip(
                  icon: Icons.date_range,
                  label: '${status.retentionWeekly} недельных',
                ),
                _Chip(
                  icon: Icons.calendar_month,
                  label: '${status.retentionMonthly} месячных',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Старые копии удаляются только после успешной проверки новой. '
              'Последняя исправная копия не удаляется.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreCard extends StatelessWidget {
  const _RestoreCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Восстановление', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Приложение проверяет архив, но не перезаписывает рабочую БД. '
              'Восстановление выполняется CLI-скриптом в новую базу и папку.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            const SelectableText(
              'age -d -i backup.key archive.zip.age > archive.zip\n'
              'unzip archive.zip -d restore\n'
              './scripts/backup/restore-verify.sh \\\n'
              '  --archive archive.zip.age \\\n'
              '  --key backup.key \\\n'
              '  --attachments-target /path/to/restored-attachments',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            _Banner(
              icon: Icons.warning_amber,
              text:
                  'Перед переключением на восстановленную БД сделайте свежую '
                  'копию рабочей. Ключ backup.key нельзя хранить только на сервере.',
              tone: _BannerTone.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptionCard extends StatelessWidget {
  const _EncryptionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Шифрование и приватность', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Архивы шифруются age ключом на сервере. Ключ хранится с правами '
              '0600, офлайн-копия — отдельно в менеджере паролей или на бумаге. '
              'Пароль от офлайн-копии не хранится на сервере.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Снимки устройств шифруются сразу при приёме. Содержимое заметок '
              'и вложений не отправляется во внешние сервисы.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum _BannerTone { info, warning, error }

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _BannerTone.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _BannerTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'нет данных';
  }
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _relative(DateTime? value) {
  if (value == null) {
    return 'нет данных';
  }
  final now = DateTime.now();
  final local = value.toLocal();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) {
    return 'сегодня';
  }
  if (days == 1) {
    return 'вчера';
  }
  return '$days дн. назад';
}

String _deviceName(String? deviceId) {
  if (deviceId == null || deviceId.isEmpty) {
    return 'неизвестно';
  }
  return '${deviceId.substring(0, 8)}…';
}
