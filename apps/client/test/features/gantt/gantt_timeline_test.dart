import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/features/gantt/domain/gantt_timeline.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

void main() {
  Task task({
    required String id,
    DateTime? plannedStart,
    DateTime? plannedEnd,
    DateTime? actualEnd,
    bool cancelled = false,
  }) {
    final now = DateTime(2026, 11, 1);
    return Task(
      id: id,
      title: id,
      description: '',
      laneId: 'lane',
      systemState: cancelled ? 'CANCELLED' : 'ACTIVE',
      categoryId: 'work',
      categoryName: 'Работа',
      priority: 'NORMAL',
      plannedStartAt: plannedStart,
      plannedEndAt: plannedEnd,
      actualStartAt: null,
      actualEndAt: actualEnd,
      revision: 1,
      syncStatus: 'SYNCED',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('строит дневной диапазон вокруг якоря', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.day);

    expect(range.start, DateTime(2026, 10, 30));
    expect(range.end, DateTime(2026, 11, 20));
    expect(range.cells, 21);
  });

  test('строит недельный диапазон с понедельника', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.week);

    expect(range.start, DateTime(2026, 10, 5));
    expect(range.end, DateTime(2026, 12, 28));
    expect(range.cells, 12);
  });

  test('строит месячный диапазон на 12 месяцев', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.month);

    expect(range.start, DateTime(2026, 5, 1));
    expect(range.end, DateTime(2027, 5, 1));
    expect(range.cells, 12);
  });

  test('перемещает якорь в зависимости от масштаба', () {
    final anchor = DateTime(2026, 11, 6);

    expect(moveGanttAnchor(anchor, GanttScale.day, 1), DateTime(2026, 11, 13));
    expect(moveGanttAnchor(anchor, GanttScale.week, -1), DateTime(2026, 10, 9));
    expect(moveGanttAnchor(anchor, GanttScale.month, 1), DateTime(2027, 2, 1));
  });

  test('рассчитывает позицию плановой полосы', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.week);
    final bar = layoutGanttBar(
      start: DateTime(2026, 11, 2),
      end: DateTime(2026, 11, 6),
      range: range,
    );

    expect(bar, isNotNull);
    expect(bar!.left, closeTo(28 / 84, 0.0001));
    expect(bar.width, closeTo(5 / 84, 0.0001));
  });

  test('обрезает полосу по границам диапазона', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.week);
    final bar = layoutGanttBar(
      start: DateTime(2026, 9, 1),
      end: DateTime(2027, 3, 1),
      range: range,
    );

    expect(bar, isNotNull);
    expect(bar!.left, 0);
    expect(bar.width, 1);
  });

  test('не возвращает полосу вне диапазона', () {
    final range = buildGanttRange(DateTime(2026, 11, 6), GanttScale.week);

    expect(
      layoutGanttBar(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 5),
        range: range,
      ),
      isNull,
    );
    expect(
      layoutGanttBar(
        start: DateTime(2027, 6, 1),
        end: DateTime(2027, 6, 5),
        range: range,
      ),
      isNull,
    );
  });

  test('определяет просрочку только для незавершённого факта', () {
    final today = DateTime(2026, 11, 6);
    final overdue = task(
      id: 'overdue',
      plannedStart: DateTime(2026, 11, 1),
      plannedEnd: DateTime(2026, 11, 4),
    );
    final completed = task(
      id: 'completed',
      plannedStart: DateTime(2026, 11, 1),
      plannedEnd: DateTime(2026, 11, 4),
      actualEnd: DateTime(2026, 11, 5),
    );
    final cancelled = task(
      id: 'cancelled',
      plannedStart: DateTime(2026, 11, 1),
      plannedEnd: DateTime(2026, 11, 4),
      cancelled: true,
    );

    expect(isGanttOverdue(overdue, today), isTrue);
    expect(isGanttOverdue(completed, today), isFalse);
    expect(isGanttOverdue(cancelled, today), isFalse);
  });
}
