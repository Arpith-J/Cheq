import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/planner_provider.dart';
import '../providers/notification_settings_provider.dart';

class WeekHeader extends ConsumerStatefulWidget {
  const WeekHeader({super.key});

  @override
  ConsumerState<WeekHeader> createState() => _WeekHeaderState();
}

class _WeekHeaderState extends ConsumerState<WeekHeader> {
  late ScrollController _scrollCtrl;
  
  // Anchor date to calculate the exact index for our infinite list
  final DateTime _anchorDate = DateTime(2022, 1, 1);
  
  double _itemWidth = 0;
  bool _isTodayVisible = true;
  DateTime _centerDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _scrollCtrl.addListener(_onScroll);

    // Jump to the currently selected day on the very first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _itemWidth = MediaQuery.of(context).size.width / 7;
        final initialDay = ref.read(selectedDayProvider);
        _centerDate = initialDay;
        _scrollToDate(initialDay, animate: false);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  int _dateToIndex(DateTime d) => DateTime(d.year, d.month, d.day).difference(_anchorDate).inDays;
  DateTime _indexToDate(int i) => _anchorDate.add(Duration(days: i));

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _itemWidth == 0) return;
    final offset = _scrollCtrl.offset;
    
    // 1. Calculate which date is currently passing through the center of the screen
    final centerIndex = (offset + (_itemWidth * 3.5)) ~/ _itemWidth;
    final newCenterDate = _indexToDate(centerIndex);

    // Update the Month/Year text if we scrolled into a new month
    if (_centerDate.month != newCenterDate.month || _centerDate.year != newCenterDate.year) {
      setState(() => _centerDate = newCenterDate);
    }

    // 2. Check if the actual "Today" block is on screen
    final todayIndex = _dateToIndex(DateTime.now());
    final todayStart = todayIndex * _itemWidth;
    final todayEnd = todayStart + _itemWidth;
    
    final viewStart = offset;
    final viewEnd = offset + (_itemWidth * 7);

    // It's visible if it falls within the boundaries of the viewport
    final isVisible = (todayEnd > viewStart) && (todayStart < viewEnd);
    
    if (_isTodayVisible != isVisible) {
      setState(() => _isTodayVisible = isVisible);
    }
  }

  void _scrollToDate(DateTime date, {bool animate = true}) {
    if (!_scrollCtrl.hasClients || _itemWidth == 0) return;
    final index = _dateToIndex(date);
    
    // Subtract 3 so the target index lands cleanly in the 4th slot (exactly in the middle of the 7 visible items).
    final targetOffset = (index - 3) * _itemWidth;

    if (animate) {
      _scrollCtrl.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollCtrl.jumpTo(targetOffset);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _weekdayShort(DateTime d) => const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d.weekday - 1];
  
  String _monthYear(DateTime d) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedDayProvider);
    final cs = Theme.of(context).colorScheme;
    final asyncEntries = ref.watch(firestorePlannerStreamProvider);
    final allEntries = asyncEntries.value ?? [];
    final showBadges = ref.watch(notificationSettingsProvider).showTaskBadges;
    final now = DateTime.now();

    // Dynamically calculate width so exactly 7 days fit regardless of screen size
    _itemWidth = MediaQuery.of(context).size.width / 7;

    // Listen to external day changes (like clicking the calendar)
    ref.listen<DateTime>(selectedDayProvider, (prev, next) {
      _scrollToDate(next);
    });

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── TOP ROW ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  _monthYear(_centerDate), // Dynamically updates as you scroll
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                
                // The Original "Today" Button
                AnimatedOpacity(
                  opacity: _isTodayVisible ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: _isTodayVisible,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          final today = DateTime.now();
                          ref.read(selectedDayProvider.notifier).changeDay(today);
                          // Explicitly trigger scroll in case the day was already set to today
                          _scrollToDate(today); 
                        },
                        icon: Icon(Icons.today_rounded, size: 16, color: cs.onPrimaryContainer), 
                        label: Text(
                          'Today',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                        ),
                      ),
                    ),
                  ),
                ),
                
                _CalendarPickerButton(selected: selectedDay),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // ── BOTTOM ROW (SNAP-TO-GRID SCROLL) ──────────────────────────
          SizedBox(
            height: 64,
            // 🎯 The NotificationListener handles the snap logic
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification is ScrollEndNotification) {
                  final double currentOffset = _scrollCtrl.offset;
                  final double targetOffset = (currentOffset / _itemWidth).round() * _itemWidth;
                  
                  // Only animate if the scroll stopped slightly off-grid
                  if ((currentOffset - targetOffset).abs() > 1.0) {
                    Future.microtask(() {
                      if (mounted) {
                        _scrollCtrl.animateTo(
                          targetOffset,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    });
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: 20000, 
                itemBuilder: (context, index) {
                  final day = _indexToDate(index);
                  final isSelected = _sameDay(day, selectedDay);
                  final isToday = _sameDay(day, now);

                  final tasksForDay = allEntries.where((t) => t.startTime.year == day.year && t.startTime.month == day.month && t.startTime.day == day.day).toList();
                  final overdueCount = tasksForDay.where((task) => !task.isDone && now.isAfter(task.endTime)).length;

                  return GestureDetector(
                    onTap: () => ref.read(selectedDayProvider.notifier).changeDay(day),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: _itemWidth,
                      child: Center(
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
                                  color: isSelected ? cs.onPrimary : isToday ? cs.onPrimaryContainer : cs.onSurface.withValues(alpha: 0.55),
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
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar Picker Button
// ---------------------------------------------------------------------------
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