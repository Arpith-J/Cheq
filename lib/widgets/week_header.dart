import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/planner_provider.dart';
import '../providers/notification_settings_provider.dart';

class WeekHeader extends ConsumerStatefulWidget {
  const WeekHeader({super.key});

  @override
  ConsumerState<WeekHeader> createState() => WeekHeaderState();
}

class WeekHeaderState extends ConsumerState<WeekHeader> {
  late PageController _pageController;
  
  // A fixed Monday in the past to act as an anchor point for our infinite math
  final DateTime _anchorDate = DateTime(2024, 1, 1); 

  int _calculatePageIndex(DateTime date) {
    // Find the Monday of the requested week
    final dateMonday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
    final daysDiff = dateMonday.difference(_anchorDate).inDays;
    return 5000 + (daysDiff ~/ 7); // Center the user around page 5000
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 5000); // Start safely in the middle
    
    // Jump to the currently selected week immediately on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialDay = ref.read(selectedDayProvider);
      _pageController.jumpToPage(_calculatePageIndex(initialDay));
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedDayProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final asyncEntries = ref.watch(firestorePlannerStreamProvider);
    final allEntries = asyncEntries.value ?? [];
    final showBadges = ref.watch(notificationSettingsProvider).showTaskBadges;

    // 🌟 SMOOTH SYNC: If the user picks a date via Calendar or "Today" button, animate to it!
    ref.listen<DateTime>(selectedDayProvider, (previous, current) {
      final targetPage = _calculatePageIndex(current);
      if (_pageController.hasClients && _pageController.page?.round() != targetPage) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
      }
    });

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _monthYear(selected),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (!_sameDay(selected, DateTime.now()))
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      final today = DateTime.now();
                      ref.read(selectedDayProvider.notifier).changeDay(today);
                    },
                    icon: Icon(Icons.today_rounded, size: 16, color: cs.onPrimaryContainer),
                    label: Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              _CalendarPickerButton(selected: selected),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: PageView.builder(
              controller: _pageController,
              // No itemCount! It scrolls infinitely
              onPageChanged: (int pageIndex) {
                // When swiping finishes, cleanly update the selected day to the new week
                final weeksDiff = pageIndex - 5000;
                final targetMonday = _anchorDate.add(Duration(days: weeksDiff * 7));
                final targetDay = targetMonday.add(Duration(days: selected.weekday - 1));
                
                if (!_sameDay(selected, targetDay)) {
                  ref.read(selectedDayProvider.notifier).changeDay(targetDay);
                }
              },
              itemBuilder: (context, pageIndex) {
                final weeksDiff = pageIndex - 5000;
                final targetMonday = _anchorDate.add(Duration(days: weeksDiff * 7));
                final weekDays = List.generate(7, (i) => targetMonday.add(Duration(days: i)));

                return Row(
                  children: weekDays.map((day) {
                    final isSelected = _sameDay(day, selected); 
                    final isToday = _sameDay(day, DateTime.now());
                    final tasksForDay = allEntries.where((t) =>
                        t.startTime.year == day.year &&
                        t.startTime.month == day.month &&
                        t.startTime.day == day.day).toList();

                    final now = DateTime.now();
                    final overdueCount = tasksForDay.where((task) {
                      return !task.isDone && now.isAfter(task.endTime);
                    }).length;  

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => ref.read(selectedDayProvider.notifier).changeDay(day),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: 40,
                          height: 60,
                          decoration: BoxDecoration(
                            color: isSelected ? cs.primary : isToday ? cs.primaryContainer : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _weekdayShort(day),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                  color: isSelected
                                      ? cs.onPrimary
                                      : isToday ? cs.onPrimaryContainer : cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Badge(
                                isLabelVisible: overdueCount > 0 && showBadges,
                                label: Text('$overdueCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                backgroundColor: Colors.redAccent, 
                                offset: const Offset(8, -8), 
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? cs.onPrimary : isToday ? cs.onPrimaryContainer : cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayShort(DateTime d) =>
      const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d.weekday - 1];

  String _monthYear(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _CalendarPickerButton extends ConsumerWidget {
  const _CalendarPickerButton({required this.selected});

  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) {
          ref.read(selectedDayProvider.notifier).changeDay(picked);
        }
      },
      icon: const Icon(Icons.calendar_month_rounded, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(36, 36),
      ),
    );
  }
}
