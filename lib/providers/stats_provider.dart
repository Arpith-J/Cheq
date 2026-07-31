import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stats_model.dart';
import 'planner_provider.dart';

final statsProvider = Provider<StatsModel>((ref) {
  final asyncTasks = ref.watch(firestorePlannerStreamProvider);
  final allTasks = asyncTasks.value ?? [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sevenDaysAgo = today.subtract(const Duration(days: 6));

  final hoursPerDayThisWeek = <DateTime, double>{};
  for (int i = 0; i < 7; i++) {
    hoursPerDayThisWeek[sevenDaysAgo.add(Duration(days: i))] = 0.0;
  }

  double totalHoursAllTime = 0.0;
  final hoursByCategory = <String, double>{};
  final heatmapHours = <DateTime, double>{};

  for (final task in allTasks) {
    if (!task.isDone) continue;

    final hours = task.endTime.difference(task.startTime).inMinutes / 60.0;
    totalHoursAllTime += hours;

    final category = task.categoryName ?? 'Uncategorized';
    hoursByCategory.update(category, (v) => v + hours, ifAbsent: () => hours);

    final taskDay = DateTime(
      task.startTime.year,
      task.startTime.month,
      task.startTime.day,
    );
    if (hoursPerDayThisWeek.containsKey(taskDay)) {
      hoursPerDayThisWeek[taskDay] = hoursPerDayThisWeek[taskDay]! + hours;
    }

    heatmapHours.update(taskDay, (v) => v + hours, ifAbsent: () => hours);
  }

  final heatmapDatasets = heatmapHours.map((date, hours) {
    final intensity = hours.round().clamp(1, 4);
    return MapEntry(date, intensity);
  });

  return StatsModel(
    totalHoursAllTime: totalHoursAllTime,
    hoursPerDayThisWeek: hoursPerDayThisWeek,
    hoursByCategory: hoursByCategory,
    heatmapDatasets: heatmapDatasets,
  );
});
