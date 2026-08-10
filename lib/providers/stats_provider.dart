import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stats_model.dart';
import 'rewards_provider.dart';

final statsProvider = Provider<StatsModel>((ref) {
  final asyncUser = ref.watch(userStreamProvider);
  final user = asyncUser.value;

  final dailyMinutesLog = user?.dailyMinutesLog ?? const <String, int>{};
  final categoryMinutes = user?.categoryMinutes ?? const <String, int>{};

  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));

  // Last 7 days, normalized to midnight (00:00:00) for the X-axis of the
  // weekly bar chart.
  final hoursPerDayThisWeek = <DateTime, double>{};
  for (int i = 0; i < 7; i++) {
    hoursPerDayThisWeek[sevenDaysAgo.add(Duration(days: i))] = 0.0;
  }

  // Banked minutes per day live on the user document, so the weekly chart
  // survives the automatic cleanup of old completed task documents.
  for (final entry in dailyMinutesLog.entries) {
    final taskMidnight = _parseDateKey(entry.key);
    if (taskMidnight == null) continue;
    if (!hoursPerDayThisWeek.containsKey(taskMidnight)) continue;
    hoursPerDayThisWeek[taskMidnight] =
        hoursPerDayThisWeek[taskMidnight]! + entry.value / 60.0;
  }

  // Lifetime totals and category breakdown come straight from the permanent
  // user ledgers instead of querying raw completed task documents.
  final totalHoursAllTime = (user?.totalMinutesLogged ?? 0) / 60.0;

  final hoursByCategory = categoryMinutes.map(
    (name, minutes) => MapEntry(name, minutes / 60.0),
  );

  final heatmapDatasets = <DateTime, int>{};
  for (final entry in dailyMinutesLog.entries) {
    final day = _parseDateKey(entry.key);
    if (day == null || entry.value <= 0) continue;
    final intensity = entry.value.round().clamp(1, 4);
    heatmapDatasets[day] =
        (heatmapDatasets[day] ?? 0) + intensity;
  }

  return StatsModel(
    totalHoursAllTime: totalHoursAllTime,
    hoursPerDayThisWeek: hoursPerDayThisWeek,
    hoursByCategory: hoursByCategory,
    heatmapDatasets: heatmapDatasets,
  );
});

/// Parses a 'YYYY-MM-DD' ledger key back into a midnight-normalized DateTime.
DateTime? _parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}
