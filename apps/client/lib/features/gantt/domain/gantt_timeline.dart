import '../../tasks/domain/task.dart';

enum GanttScale { day, week, month }

class GanttRange {
  const GanttRange({
    required this.start,
    required this.end,
    required this.cells,
    required this.scale,
  });

  final DateTime start;
  final DateTime end;
  final int cells;
  final GanttScale scale;
}

GanttRange buildGanttRange(DateTime anchor, GanttScale scale) {
  final date = _dateOnly(anchor);
  switch (scale) {
    case GanttScale.day:
      final start = date.subtract(const Duration(days: 7));
      return GanttRange(
        start: start,
        end: start.add(const Duration(days: 21)),
        cells: 21,
        scale: scale,
      );
    case GanttScale.week:
      final offset = (date.weekday - DateTime.monday) % 7;
      final start = date.subtract(Duration(days: offset + 28));
      return GanttRange(
        start: start,
        end: start.add(const Duration(days: 84)),
        cells: 12,
        scale: scale,
      );
    case GanttScale.month:
      final start = DateTime(date.year, date.month - 6, 1);
      return GanttRange(
        start: start,
        end: DateTime(start.year, start.month + 12, 1),
        cells: 12,
        scale: scale,
      );
  }
}

DateTime moveGanttAnchor(DateTime anchor, GanttScale scale, int direction) {
  switch (scale) {
    case GanttScale.day:
      return anchor.add(Duration(days: 7 * direction));
    case GanttScale.week:
      return anchor.add(Duration(days: 28 * direction));
    case GanttScale.month:
      return DateTime(anchor.year, anchor.month + 3 * direction, 1);
  }
}

class GanttBarLayout {
  const GanttBarLayout({required this.left, required this.width});

  final double left;
  final double width;
}

GanttBarLayout? layoutGanttBar({
  required DateTime? start,
  required DateTime? end,
  required GanttRange range,
}) {
  var first = start == null ? null : _dateOnly(start);
  var last = end == null ? null : _dateOnly(end);
  if (first == null && last == null) {
    return null;
  }
  first ??= last;
  last ??= first;
  if (last!.isBefore(first!)) {
    final swap = first;
    first = last;
    last = swap;
  }

  final rangeStart = _dateOnly(range.start);
  final rangeEnd = _dateOnly(range.end);
  final lastExclusive = last.add(const Duration(days: 1));
  if (last.isBefore(rangeStart)) {
    return null;
  }
  if (!first.isBefore(rangeEnd)) {
    return null;
  }

  final totalDays = rangeEnd.difference(rangeStart).inDays;
  if (totalDays <= 0) {
    return null;
  }
  final clampedStart = first.isBefore(rangeStart) ? rangeStart : first;
  final clampedEnd = lastExclusive.isAfter(rangeEnd) ? rangeEnd : lastExclusive;
  final leftDays = clampedStart.difference(rangeStart).inDays;
  final widthDays = clampedEnd.difference(clampedStart).inDays;
  if (widthDays <= 0) {
    return null;
  }
  return GanttBarLayout(
    left: (leftDays / totalDays).clamp(0, 1),
    width: (widthDays / totalDays).clamp(0, 1),
  );
}

bool isGanttOverdue(Task task, DateTime today) {
  if (task.isCancelled || task.plannedEndAt == null) {
    return false;
  }
  final plannedEnd = _dateOnly(task.plannedEndAt!.toLocal());
  final actualEnd = task.actualEndAt == null
      ? null
      : _dateOnly(task.actualEndAt!.toLocal());
  return plannedEnd.isBefore(_dateOnly(today)) && actualEnd == null;
}

bool ganttTaskHasDates(Task task) =>
    task.plannedStartAt != null ||
    task.plannedEndAt != null ||
    task.actualStartAt != null ||
    task.actualEndAt != null;

DateTime _dateOnly(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day);
}
