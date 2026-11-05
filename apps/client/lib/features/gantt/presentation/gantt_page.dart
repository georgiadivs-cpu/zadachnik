import 'package:flutter/material.dart';

import '../../../app/placeholder_page.dart';

class GanttPage extends StatelessWidget {
  const GanttPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Гант',
      description:
          'Простая временная шкала задач с плановыми '
          'и фактическими датами.',
    );
  }
}
