import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../sync/application/sync_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final sync = ref.watch(syncControllerProvider);
    final session = auth.session;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Text('Я')),
              title: Text(session?.email ?? 'Локальный режим'),
              subtitle: Text(
                session == null
                    ? 'Сессия не найдена'
                    : auth.offline
                    ? 'Сервер недоступен · локальные данные доступны'
                    : 'Сессия активна',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: sync.isRunning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      sync.phase == SyncPhase.offline ||
                              sync.phase == SyncPhase.error
                          ? Icons.cloud_off
                          : Icons.cloud_done_outlined,
                    ),
              title: Text(_syncTitle(sync)),
              subtitle: Text(
                sync.phase == SyncPhase.error
                    ? sync.message ?? 'Ошибка синхронизации'
                    : 'Отправлено: ${sync.pushed} · получено: ${sync.pulled} · конфликтов: ${sync.conflicts}',
              ),
              trailing: TextButton(
                onPressed: sync.isRunning
                    ? null
                    : () => ref.read(syncControllerProvider.notifier).sync(),
                child: const Text('Синхронизировать'),
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('Локальное хранилище'),
              subtitle: Text(
                'SQLite + Drift. Заметки сохраняются до синхронизации.',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.sync_outlined),
              title: Text('Синхронизация заметок'),
              subtitle: Text(
                'Push/pull по cursor. Конфликты сохраняются до ручного решения.',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('AI Approval'),
              subtitle: Text(
                'Изменения AI применяются только после подтверждения.',
              ),
            ),
          ),
          if (session != null)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Выйти',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Локальные заметки останутся на устройстве',
                ),
                onTap: () => _logout(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  static String _syncTitle(SyncViewState sync) => switch (sync.phase) {
    SyncPhase.running => 'Синхронизация…',
    SyncPhase.success => 'Синхронизировано',
    SyncPhase.offline => 'Сервер недоступен',
    SyncPhase.error => 'Ошибка синхронизации',
    SyncPhase.idle => 'Синхронизация',
  };
}
