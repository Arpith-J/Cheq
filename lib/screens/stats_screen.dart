import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/rewards_provider.dart';
import '../providers/stats_provider.dart';

/// Timeframe window for the activity heatmap, with its day span.
enum _StatsRange {
  month(30),
  threeMonths(90),
  sixMonths(180),
  year(365);

  const _StatsRange(this.days);

  final int days;
}

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  static const _pieColors = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF607D8B),
  ];

  static const _weekdayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  int _touchedPieIndex = -1;
  _StatsRange _range = _StatsRange.month;

  static String _formatHours(double totalHours) {
    final totalMinutes = (totalHours * 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '$hours hr';
    return '$hours hr ${minutes}m';
  }

  /// Converts the permanent 'YYYY-MM-DD' ledger keys into DateTime keys,
  /// keeping only the entries on or after [startDate] (the day the selected
  /// timeframe window begins). The grid is then bounded by the same dates.
  static Map<DateTime, int> _filteredActivityLog(
    Map<String, int> log,
    DateTime startDate,
  ) {
    final result = <DateTime, int>{};
    log.forEach((key, count) {
      if (count <= 0) return;
      final parts = key.split('-');
      if (parts.length != 3) return;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return;

      final date = DateTime(y, m, d);
      if (date.isBefore(startDate)) return;
      result[date] = count.clamp(1, 4);
    });
    return result;
  }

  void _onPieTouch(FlTouchEvent event, PieTouchResponse? response) {
    setState(() {
      if (!event.isInterestedForInteractions ||
          response == null ||
          response.touchedSection == null) {
        _touchedPieIndex = -1;
        return;
      }
      _touchedPieIndex = response.touchedSection!.touchedSectionIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final userAsync = ref.watch(userStreamProvider);
    final cs = Theme.of(context).colorScheme;

    final user = userAsync.value;
    // Lifetime minutes are banked on the user doc in Firestore so the stat is
    // immune to tasks being deleted after they're checked off.
    final totalMinutesLogged = user?.totalMinutesLogged ?? 0;

    // Permanent ledger: category minutes survive task deletion.
    final sortedCategories = (user?.categoryMinutes ?? const <String, int>{})
        .entries
        .map((e) => MapEntry(e.key, e.value / 60.0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Permanent ledger: activity heatmap, strictly limited to the selected
    // timeframe window. The start date drives both the dataset filter and the
    // rendered grid bounds so the heatmap resizes with the 1M/3M/6M/1Y filter.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: _range.days));
    final heatmapDatasets = _filteredActivityLog(
      user?.dailyActivityLog ?? const {},
      startDate,
    );

    final sortedDays = stats.hoursPerDayThisWeek.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    double maxY = 1.0;
    if (sortedDays.isNotEmpty) {
      maxY = sortedDays.map((e) => e.value).reduce(max).ceilToDouble();
      if (maxY < 1.0) maxY = 1.0;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Time Breakdown')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Column(
                children: [
                  Text(
                    'Total Time Logged',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatHours(totalMinutesLogged / 60.0),
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Hours by Category',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (sortedCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No data yet',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 50,
                          sections: _buildPieSections(sortedCategories),
                          pieTouchData: PieTouchData(
                            touchCallback: _onPieTouch,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _touchedPieIndex >= 0 ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: _buildPieTooltip(sortedCategories, cs),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _buildLegend(sortedCategories, cs),
                ),
              ],
            ),
          const SizedBox(height: 32),
          Text(
            'Hours This Week',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex >= sortedDays.length) return null;
                      final day = sortedDays[groupIndex].key;
                      final label = _weekdayLabels[day.weekday - 1];
                      return BarTooltipItem(
                        '$label\n${_formatHours(rod.toY)}',
                        TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sortedDays.length) return const SizedBox.shrink();
                        final day = sortedDays[idx].key;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _weekdayLabels[day.weekday - 1],
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}h',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: sortedDays.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: cs.primary,
                        width: 20,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Long-Term Consistency',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SegmentedButton<_StatsRange>(
                    segments: const [
                      ButtonSegment(
                        value: _StatsRange.month,
                        label: Text('1 Month'),
                      ),
                      ButtonSegment(
                        value: _StatsRange.threeMonths,
                        label: Text('3 Months'),
                      ),
                      ButtonSegment(
                        value: _StatsRange.sixMonths,
                        label: Text('6 Months'),
                      ),
                      ButtonSegment(
                        value: _StatsRange.year,
                        label: Text('1 Year'),
                      ),
                    ],
                    selected: {_range},
                    onSelectionChanged: (selection) =>
                        setState(() => _range = selection.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 16),
                  if (heatmapDatasets.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No data yet',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    HeatMap(
                      datasets: heatmapDatasets,
                      startDate: startDate,
                      endDate: today,
                      colorMode: ColorMode.color,
                      colorsets: {
                        1: const Color(0xFF9BE9A8),
                        2: const Color(0xFF40C463),
                        3: const Color(0xFF30A14E),
                        4: const Color(0xFF216E39),
                      },
                      defaultColor: cs.surfaceContainerHighest,
                      textColor: cs.onSurfaceVariant,
                      showText: false,
                      showColorTip: false,
                      scrollable: true,
                      size: 18,
                      borderRadius: 4,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieTooltip(List<MapEntry<String, double>> data, ColorScheme cs) {
    final index = _touchedPieIndex;
    if (index < 0 || index >= data.length) return const SizedBox.shrink();
    final entry = data[index];
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.key,
              style: TextStyle(
                color: cs.onInverseSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatHours(entry.value),
              style: TextStyle(
                color: cs.onInverseSurface,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(List<MapEntry<String, double>> data) {
    final total = data.fold(0.0, (a, b) => a + b.value);
    if (total == 0) return [];
    return data.asMap().entries.map((e) {
      final percentage = (e.value.value / total * 100).toStringAsFixed(1);
      final isTouched = e.key == _touchedPieIndex;
      return PieChartSectionData(
        color: _pieColors[e.key % _pieColors.length],
        value: e.value.value,
        title: '$percentage%',
        radius: isTouched ? 60 : 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<Widget> _buildLegend(List<MapEntry<String, double>> data, ColorScheme cs) {
    return data.asMap().entries.map((e) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _pieColors[e.key % _pieColors.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${e.value.key} (${_formatHours(e.value.value)})',
                style: TextStyle(fontSize: 12, color: cs.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
