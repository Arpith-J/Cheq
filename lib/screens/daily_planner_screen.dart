import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide RepeatInterval;
import 'package:timezone/data/latest_10y.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../models/planner_model.dart';
import '../providers/planner_provider.dart';
import '../services/firestore_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Etc/UTC'));
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      androidPlugin.requestExactAlarmsPermission();
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    _initialized = true;
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!_initialized) await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cheq_planner_channel',
        'Daily Planner',
        channelDescription: 'Reminders for your daily planner tasks',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id: id);
}

final selectedDayProvider = NotifierProvider(
  SelectedDayNotifier.new,
);

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void changeDay(DateTime newDay) {
    state = DateTime(newDay.year, newDay.month, newDay.day);
  }
}

final selectedDayEntriesProvider =
    NotifierProvider<SelectedDayEntriesNotifier, List<PlannerModel>>(
  SelectedDayEntriesNotifier.new,
);

class SelectedDayEntriesNotifier extends Notifier<List<PlannerModel>> {
  @override
  List<PlannerModel> build() {
    final day = ref.watch(selectedDayProvider);
    final asyncEntries = ref.watch(firestorePlannerStreamProvider);
    final entries = asyncEntries.value ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return entries.where((e) {
      final taskDay = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      if (taskDay == day) return true;
      if (day == today && taskDay.isBefore(today) && !e.isDone) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}

class DailyPlannerScreen extends ConsumerWidget {
  const DailyPlannerScreen({super.key});

  void _openAddSheet(BuildContext context, WidgetRef ref,
      {PlannerModel? initialEntry}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _AddTaskSheet(initialEntry: initialEntry),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _WeekHeader(),
          Expanded(child: _TaskFeed()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Task'),
      ),
    );
  }
}

class _WeekHeader extends ConsumerStatefulWidget {
  const _WeekHeader();

  @override
  ConsumerState<_WeekHeader> createState() => _WeekHeaderState();
}

class _WeekHeaderState extends ConsumerState<_WeekHeader> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
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
                      _pageController.jumpToPage(1);
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
              itemCount: 3,
              onPageChanged: (int pageIndex) {
                if (pageIndex == 1) return;
                final weekOffset = pageIndex == 2 ? 7 : -7;
                final targetDay = selected.add(Duration(days: weekOffset));
                ref.read(selectedDayProvider.notifier).changeDay(targetDay);
                _pageController.jumpToPage(1);
              },
              itemBuilder: (context, pageOffsetIndex) {
                final weekShiftDays = (pageOffsetIndex - 1) * 7;
                final targetCalculatedDay = selected.add(Duration(days: weekShiftDays));
                final weekDays = _buildWeek(targetCalculatedDay);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: weekDays.map((day) {
                    final isSelected = _sameDay(day, selected);
                    final isToday = _sameDay(day, DateTime.now());

                    return GestureDetector(
                      onTap: () => ref.read(selectedDayProvider.notifier).changeDay(day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 40,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : isToday
                                  ? cs.primaryContainer
                                  : Colors.transparent,
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
                                    : isToday
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? cs.onPrimary
                                    : isToday
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface,
                              ),
                            ),
                          ],
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

  List<DateTime> _buildWeek(DateTime day) {
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
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

class _TaskFeed extends ConsumerWidget {
  const _TaskFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(selectedDayEntriesProvider);
    if (entries.isEmpty) return const _EmptyDay();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: entries.length,
      itemBuilder: (_, i) => _TaskRow(entry: entries[i]),
    );
  }
}

class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({required this.entry});

  final PlannerModel entry;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation _strikeAnim;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.entry.isDone ? 1.0 : 0.0,
    );
    _strikeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(_TaskRow old) {
    super.didUpdateWidget(old);
    if (widget.entry.isDone != old.entry.isDone) {
      widget.entry.isDone ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTimeString(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<bool> _showDeleteConfirmDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Task',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content:
                const Text('Are you sure you want to permanently delete this task?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cs.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entry = widget.entry;
    final now = DateTime.now();
    final taskDay = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);
    final today = DateTime(now.year, now.month, now.day);

    final isOverdue = !entry.isDone && 
        (taskDay.isBefore(today) || (taskDay.isAtSameMomentAs(today) && now.isAfter(entry.endTime)));

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        try {
          await FirestoreService.instance.deleteTask(entry.id);
          return true; // Confirms removal to the animation tree safely
        } catch (e) {
          debugPrint("Error dismissing: $e");
          return false;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOverdue
                ? cs.error.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.5),
            width: isOverdue ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          onLongPress: () async {
            final confirmed = await _showDeleteConfirmDialog(context);
            if (confirmed && mounted) {
              await FirestoreService.instance.deleteTask(entry.id);
            }
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 82,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 4),
                        alignment: Alignment.center,
                        child: Text(
                          _formatTimeString(entry.startTime),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: entry.isDone
                                ? cs.onSurface.withValues(alpha: 0.3)
                                : cs.primary,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        color: entry.isDone
                            ? cs.outlineVariant.withValues(alpha: 0.3)
                            : cs.primary.withValues(alpha: 0.35),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedBuilder(
                                  animation: _strikeAnim,
                                  builder: (_, _) => Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isOverdue)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: cs.errorContainer,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'OVERDUE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: cs.onErrorContainer,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Text(
                                        entry.title,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: entry.isDone
                                              ? cs.onSurface.withValues(alpha: 0.35)
                                              : isOverdue
                                                  ? cs.error
                                                  : cs.onSurface,
                                          decoration: entry.isDone
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          decorationColor:
                                              cs.onSurface.withValues(alpha: 0.4),
                                          decorationThickness: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (entry.isNotified)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.notifications_active_rounded,
                                    size: 14,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                ),
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: entry.isDone,
                                  onChanged: (bool? isChecked) async {
                                    final updatedTask =
                                        entry.copyWith(isDone: isChecked ?? false);
                                    await FirestoreService.instance
                                        .saveTask(updatedTask);
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(79, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                            height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'Duration: ${_formatTimeString(entry.startTime)} - ${_formatTimeString(entry.endTime)}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.sync_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Repeats: ${entry.repeatInterval.name.toUpperCase()}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  builder: (_) => UncontrolledProviderScope(
                                    container: ProviderScope.containerOf(context),
                                    child: _AddTaskSheet(initialEntry: entry),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit_rounded, size: 14),
                              label:
                                  const Text('Edit', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_rounded,
              size: 64, color: cs.onSurface.withValues(alpha: 0.12)),
          const SizedBox(height: 16),
          Text(
            'Nothing scheduled',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the button below to add a task.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
          ),
        ],
      ),
    );
  }
}

class _AddTaskSheet extends ConsumerStatefulWidget {
  final PlannerModel? initialEntry;

  const _AddTaskSheet({this.initialEntry});

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  late final TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();

  bool _isSaving = false;
  bool _notifyMe = false;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late RepeatInterval _repeatInterval;
  Duration? _customInterval;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;

    _titleCtrl = TextEditingController(text: entry?.title ?? '');
    _notifyMe = entry?.isNotified ?? false;
    _repeatInterval = entry?.repeatInterval ?? RepeatInterval.none;
    _customInterval = entry?.customInterval;

    if (entry != null) {
      _startTime = TimeOfDay.fromDateTime(entry.startTime);
      _endTime = TimeOfDay.fromDateTime(entry.endTime);
    } else {
      _startTime = TimeOfDay.now();
      _endTime = TimeOfDay(
        hour: (_startTime.hour + 1) % 24,
        minute: _startTime.minute,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startTime = picked;
        final startMins = picked.hour * 60 + picked.minute;
        final endMins = _endTime.hour * 60 + _endTime.minute;
        if (endMins <= startMins) {
          final advanced = startMins + 60;
          _endTime = TimeOfDay(
            hour: (advanced ~/ 60) % 24,
            minute: advanced % 60,
          );
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _showCustomIntervalDialog() async {
    final ctrl = TextEditingController();
    final steps = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Interval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Repeat every X days',
            hintText: 'e.g. 3',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    ctrl.dispose();

    if (steps != null && steps > 0) {
      setState(() => _customInterval = Duration(days: steps));
    } else {
      setState(() {
        _repeatInterval = RepeatInterval.none;
        _customInterval = null;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving || _titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);

    try {
      final day = ref.read(selectedDayProvider);

      DateTime toDateTime(TimeOfDay t) =>
          DateTime(day.year, day.month, day.day, t.hour, t.minute);

      final startDt = toDateTime(_startTime);
      final endDt = toDateTime(_endTime);

      final String targetId = widget.initialEntry?.id ?? 
          'entry_${DateTime.now().millisecondsSinceEpoch}';

      final entry = PlannerModel(
        id: targetId,
        title: _titleCtrl.text.trim(),
        startTime: startDt,
        endTime: endDt,
        isDone: widget.initialEntry?.isDone ?? false,
        isNotified: _notifyMe,
        repeatInterval: _repeatInterval,
        customInterval: _customInterval,
      );

      await FirestoreService.instance.saveTask(entry);

      // 🌟 FIX: Apply identical 32-bit integer compression constraints
      final rawDigits = targetId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedInt = int.tryParse(rawDigits);
      
      final int stableNotificationId = parsedInt != null 
          ? (parsedInt % 2147483647) 
          : targetId.hashCode;
      
      await NotificationService.instance.cancelNotification(stableNotificationId);

      if (_notifyMe) {
        unawaited(
          NotificationService.instance.scheduleNotification(
            id: stableNotificationId,
            title: 'Moon Reminder',
            body: _titleCtrl.text.trim(),
            scheduledTime: startDt,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Error inside save calculation routine: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    widget.initialEntry != null ? 'Edit Task' : 'New Task',
                    style:
                        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                focusNode: _titleFocus,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'What do you need to do?',
                  hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeTile(
                      label: 'Start',
                      time: _startTime,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeTile(
                      label: 'End',
                      time: _endTime,
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      size: 18,
                      color: _repeatInterval != RepeatInterval.none
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Text('Repeat',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const Spacer(),
                    DropdownButton<RepeatInterval>(
                      value: _repeatInterval,
                      underline: const SizedBox(),
                      dropdownColor: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      onChanged: (RepeatInterval? newVal) {
                        if (newVal == null) return;
                        setState(() => _repeatInterval = newVal);
                        if (newVal == RepeatInterval.custom) {
                          _showCustomIntervalDialog();
                        } else {
                          _customInterval = null;
                        }
                      },
                      items: RepeatInterval.values.map((val) {
                        String display = val.name.toUpperCase();
                        if (val == RepeatInterval.custom && _customInterval != null) {
                          display = '${_customInterval!.inDays} DAYS';
                        }
                        return DropdownMenuItem(
                          value: val,
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _notifyMe ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                      size: 18,
                      color: _notifyMe ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    const Text('Notify me'),
                    const Spacer(),
                    Switch.adaptive(
                      value: _notifyMe,
                      onChanged: (v) => setState(() => _notifyMe = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text =
        '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}:${time.minute.toString().padLeft(2, '0')} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}