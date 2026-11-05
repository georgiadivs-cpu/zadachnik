import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

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
              title: Text('Синхронизация'),
              subtitle: Text(
                'Сервер и токены готовы. Клиентский sync — следующий шаг.',
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
                subtitle: const Text('Локальные заметки останутся на устройстве'),
                onTap: () => _logout(context, ref),
              ),
            ),
        ],
      ),
    );
  }
}
