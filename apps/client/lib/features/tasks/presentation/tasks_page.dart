import 'package:flutter/material.dart';

import '../../../app/placeholder_page.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Задачи',
      description:
          'Одна доска с настраиваемыми дорожками, '
          'самостоятельными задачами и связями с чек-листами.',
    );
  }
}
