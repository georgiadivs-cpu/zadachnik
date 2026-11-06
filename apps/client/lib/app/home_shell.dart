import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/calendar/application/calendar_providers.dart';
import '../features/ai/presentation/ai_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/gantt/presentation/gantt_page.dart';
import '../features/notes/presentation/notes_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/sync/application/sync_controller.dart';
import '../features/tasks/presentation/tasks_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(reminderCoordinatorProvider).reconcile();
      } on Object {
        // Ошибка уведомлений не должна блокировать работу приложения.
      }
      await ref.read(syncControllerProvider.notifier).sync();
    });
  }

  static const _pages = <Widget>[
    NotesPage(),
    TasksPage(),
    CalendarPage(),
    GanttPage(),
    AiPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Заметки',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_kanban_outlined),
            selectedIcon: Icon(Icons.view_kanban),
            label: 'Задачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'Гант',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
