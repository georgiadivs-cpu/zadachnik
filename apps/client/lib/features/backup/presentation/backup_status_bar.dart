import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../auth/application/auth_controller.dart';
import '../application/backup_providers.dart';
import '../domain/backup_models.dart';
import 'backup_page.dart';

class BackupStatusHost extends ConsumerStatefulWidget {
  const BackupStatusHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupStatusHost> createState() => _BackupStatusHostState();
}

class _BackupStatusHostState extends ConsumerState<BackupStatusHost> {
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
        ref.read(backupControllerProvider.notifier).refresh(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureStarted() {
    if (_started) {
      return;
    }
    _started = true;
    Future.microtask(() {
      if (mounted) {
        ref.read(backupControllerProvider.notifier).initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (next.status != AuthStatus.authenticated ||
          previous?.status != AuthStatus.authenticated) {
        _started = false;
      }
    });
    final auth = ref.watch(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) {
      return widget.child;
    }
    _ensureStarted();
    final state = ref.watch(backupControllerProvider);
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          _BackupStatusBar(
            state: state,
            onTap: () {
              appNavigatorKey.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (context) => const BackupPage(),
                ),
              );
            },
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _BackupStatusBar extends StatelessWidget {
  const _BackupStatusBar({required this.state, required this.onTap});

  final BackupViewState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = state.status;
    final presentation = _presentation(status, state, scheme);
    return Material(
      color: presentation.background,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 27,
          child: Row(
            children: [
              const SizedBox(width: 12),
              if (status?.running == true)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: presentation.foreground,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: presentation.foreground,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  presentation.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: presentation.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ),
              if (status != null && status.diskFreeBytes > 0) ...[
                Text(
                  'Диск: ${formatBytes(status.diskFreeBytes)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: presentation.foreground.withValues(alpha: 0.72),
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _BarPresentation _presentation(
    BackupStatusSnapshot? status,
    BackupViewState state,
    ColorScheme scheme,
  ) {
    if (status == null) {
      if (state.offline) {
        return _BarPresentation(
          label: 'Бэкап: нет связи',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        );
      }
      return _BarPresentation(
        label: 'Бэкап: статус загружается…',
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      );
    }
    if (status.running) {
      return _BarPresentation(
        label: status.operation == 'VERIFY'
            ? 'Бэкап: проверка копии…'
            : 'Бэкап: идёт копирование…',
        background: const Color(0xFFE5EEF6),
        foreground: const Color(0xFF3E6280),
      );
    }
    if (!status.configured) {
      return _BarPresentation(
        label: 'Бэкап: не настроен',
        background: const Color(0xFFFBE9E7),
        foreground: const Color(0xFF8A3832),
      );
    }
    if (state.offline) {
      return _BarPresentation(
        label: 'Бэкап: нет связи · ${_relative(status.lastVerifiedAt)}',
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      );
    }
    if (status.lastError != null || state.error != null) {
      return _BarPresentation(
        label: 'Бэкап: ошибка · нажмите для деталей',
        background: const Color(0xFFFBE9E7),
        foreground: const Color(0xFF8A3832),
      );
    }
    final verified = status.latestArchive?.verified == true;
    if (!verified) {
      return _BarPresentation(
        label: 'Бэкап: нет проверенной копии',
        background: const Color(0xFFFDF3DF),
        foreground: const Color(0xFF8A6428),
      );
    }
    final age = status.lastVerifiedAt == null
        ? null
        : DateTime.now().difference(status.lastVerifiedAt!);
    final stale = age != null && age.inDays >= 7;
    return _BarPresentation(
      label: stale
          ? 'Бэкап: ${age.inDays} дн. назад · пора создать копию'
          : 'Бэкап: ${_relative(status.lastVerifiedAt)} · проверено',
      background: stale ? const Color(0xFFFDF3DF) : const Color(0xFFE3F2E8),
      foreground: stale ? const Color(0xFF8A6428) : const Color(0xFF2E6248),
    );
  }
}

class _BarPresentation {
  const _BarPresentation({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

String _relative(DateTime? value) {
  if (value == null) {
    return 'нет данных';
  }
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  if (date == today) {
    return 'сегодня $time';
  }
  if (date == today.subtract(const Duration(days: 1))) {
    return 'вчера $time';
  }
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')} $time';
}

String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '—';
  }
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
