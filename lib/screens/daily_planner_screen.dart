// lib/screens/daily_planner_screen.dart
//
// Requires (your pubspec.yaml already has these):
//   flutter_riverpod: ^3.3.2
//   flutter_local_notifications: ^22.0.1   ← v20+ uses ALL named params
//   timezone: ^0.11.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide RepeatInterval;
import 'package:timezone/data/latest_10y.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../models/planner_model.dart';
import '../providers/planner_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE
// flutter_local_notifications ≥ 20.0.0 converted ALL positional params
// to named params in initialize(), show(), zonedSchedule(), cancel() etc.
// UILocalNotificationDateInterpretation was removed in 19.0.0.
// ════════════════════════════════════════════════════════════════════════════

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
      // 2. Query the native hardware architecture string (e.g., 'Asia/Kolkata')
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZoneInfo.identifier;
      // 3. Bind the local engine reference securely
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      // Fallback baseline parameter to prevent runtime crashes if location fails
      tz.setLocalLocation(tz.getLocation('Etc/UTC'));
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
        
    // v20+: initialize() now takes named parameter `settings`
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
    required int      id,
    required String   title,
    required String   body,
    required DateTime scheduledTime,
  }) async {
    if (!_initialized) await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cheq_planner_channel',
        'Daily Planner',
        channelDescription: 'Reminders for your daily planner tasks',
        importance: Importance.high,
        priority:   Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
      await _plugin.zonedSchedule(
      id:                  id,
      title:               title,
      body:                body,
      scheduledDate:       tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // v20+: cancel() also uses named param `id`
  Future<void> cancelNotification(int id) async =>
      await _plugin.cancel(id: id);
}

// ════════════════════════════════════════════════════════════════════════════
// SCREEN-LOCAL PROVIDERS (Riverpod 3.x Compliant Notifier Patterns)
// ════════════════════════════════════════════════════════════════════════════

// 1. Replaced StateProvider with the modern NotifierProvider pattern
final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
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

// Guard to prevent mock data from being seeded more than once.
bool _mockSeeded = false;

// 2. Replaced legacy functional 'Provider' with a modern read-only Functional Notifier
final selectedDayEntriesProvider = NotifierProvider<SelectedDayEntriesNotifier, List<PlannerModel>>(
  SelectedDayEntriesNotifier.new,
);

class SelectedDayEntriesNotifier extends Notifier<List<PlannerModel>> {
  @override
  List<PlannerModel> build() {
    // ref.watch behaves identically inside a Notifier's build method
    final day     = ref.watch(selectedDayProvider);
    final entries = ref.watch(plannerProvider);
    
    return entries
        .where((e) =>
            e.startTime.year  == day.year &&
            e.startTime.month == day.month &&
            e.startTime.day   == day.day)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DAILY PLANNER SCREEN
// ════════════════════════════════════════════════════════════════════════════

class DailyPlannerScreen extends ConsumerWidget {
  const DailyPlannerScreen({super.key});

  void _seedMockData(WidgetRef ref) {
    if (_mockSeeded) return;
    _mockSeeded = true;

    final now  = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);

    DateTime s(int h, int m) => base.add(Duration(hours: h, minutes: m));
    DateTime e(int h, int m) => base.add(Duration(hours: h, minutes: m));

    final seeds = [
      PlannerModel(id: 's1', title: 'Morning standup',       startTime: s(9,  0),  endTime: e(9,  30)),
      PlannerModel(id: 's2', title: 'Review pull requests', startTime: s(10, 30), endTime: e(11, 30)),
      PlannerModel(id: 's3', title: 'Lunch with the team',  startTime: s(13, 0),  endTime: e(14, 0)),
      PlannerModel(id: 's4', title: 'Design system review', startTime: s(15, 0),  endTime: e(16, 0)),
      PlannerModel(id: 's5', title: 'Write release notes',  startTime: s(16, 30), endTime: e(17, 0)),
      PlannerModel(id: 's6', title: 'Evening workout',       startTime: s(18, 0),  endTime: e(19, 0)),
    ];

    // ── FIX 1: Wrap the state modification in a PostFrameCallback ───────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final seed in seeds) {
        ref.read(plannerProvider.notifier).addEntry(seed);
      }
    });
    // ────────────────────────────────────────────────────────────────────────
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Flipped safe gate runs here, but execution is safely deferred until the frame finishes drawing
    _seedMockData(ref);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      // ── FIX 2: Remove the 'const' keyword here ────────────────────────────
      // (Column can no longer be const because _TaskFeed internally watches the active providers)
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _WeekHeader(),
          Expanded(child: _TaskFeed()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context, ref),
        icon:  const Icon(Icons.add_rounded),
        label: const Text('Add Task'),
      ),
    );
  }

  void _openAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child:     const _AddTaskSheet(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WEEK HEADER
// ════════════════════════════════════════════════════════════════════════════

class _WeekHeader extends ConsumerWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDayProvider);
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final weekDays = _buildWeek(selected);

    return Container(
      color:   cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _monthYear(selected),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight:    FontWeight.w800,
                  color:         cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              _CalendarPickerButton(selected: selected),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekDays.map((day) {
              final isSelected = _sameDay(day, selected);
              final isToday    = _sameDay(day, DateTime.now());
              return GestureDetector(
                onTap: () => ref.read(selectedDayProvider.notifier).changeDay(day),
                child: AnimatedContainer(
                  duration:    const Duration(milliseconds: 200),
                  curve:       Curves.easeOutCubic,
                  width:       40,
                  height:      60,
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
                          fontSize:      11,
                          fontWeight:    FontWeight.w600,
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
                          fontSize:   16,
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
      'January', 'February', 'March',     'April',   'May',      'June',
      'July',    'August',   'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CALENDAR PICKER BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _CalendarPickerButton extends ConsumerWidget {
  const _CalendarPickerButton({required this.selected});

  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: () async {
        final picked = await showDatePicker(
          context:     context,
          initialDate: selected,
          firstDate:   DateTime(2020),
          lastDate:    DateTime(2035),
        );
        if (picked != null) {
          ref.read(selectedDayProvider.notifier).changeDay(picked);
        }
      },
      icon:  const Icon(Icons.calendar_month_rounded, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        padding:         const EdgeInsets.all(8),
        minimumSize:     const Size(36, 36),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TASK FEED
// ════════════════════════════════════════════════════════════════════════════

class _TaskFeed extends ConsumerWidget {
  const _TaskFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(selectedDayEntriesProvider);
    if (entries.isEmpty) return const _EmptyDay();
    return ListView.builder(
      padding:     const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount:   entries.length,
      itemBuilder: (_, i) => _TaskRow(entry: entries[i]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TASK ROW
// ════════════════════════════════════════════════════════════════════════════

class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({required this.entry});

  final PlannerModel entry;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>    _strikeAnim;
  
  // ── FIX 1: Add the expanded layout visibility state tracking flag ───────
  bool _isExpanded = false; 

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 350),
      value:    widget.entry.isDone ? 1.0 : 0.0,
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

  // Helper method to format standard time strings cleanly for the details sub-panel
  String _formatTimeString(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<bool> _showDeleteConfirmDialog(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: const Text('Are you sure you want to permanently delete this task?'),
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
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final notifier = ref.read(plannerProvider.notifier);
    final entry    = widget.entry;

    return Dismissible(
      key:        Key(entry.id),
      direction:  DismissDirection.endToStart,
      background: Container(
        alignment:  Alignment.centerRight,
        padding:    const EdgeInsets.only(right: 20),
        margin:     const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color:        cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => notifier.removeEntry(entry.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color:        cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        // ── FIX 2: Wrap inside InkWell to make the entire task card tappable ──
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          onLongPress: () async {
            final confirmed = await _showDeleteConfirmDialog(context);
            if (confirmed && mounted) {
                ref.read(plannerProvider.notifier).removeEntry(entry.id);
            }
          },  
          // ── FIX 3: Wrap inside AnimatedSize for smooth resizing animations ──
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
                      // ── Time Gutter ────────────────────────────────────────
                      Container(
                        width: 82, // Explicit width gives "12:00 PM" plenty of horizontal room
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        alignment: Alignment.center, // Centers the time text inside its gutter space
                        child: Text(
                          _formatTimeString(entry.startTime), // Single string output: "09:00 AM"
                          maxLines: 1, // Strictly forbids vertical wrapping
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

                      // ── Accent Separator Line ──────────────────────────────
                      Container(
                        width:  1,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        color:  entry.isDone
                            ? cs.outlineVariant.withValues(alpha: 0.3)
                            : cs.primary.withValues(alpha: 0.35),
                      ),

                      // ── Core Row Content ───────────────────────────────────
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedBuilder(
                                  animation: _strikeAnim,
                                  builder: (_, _) => Text(
                                    entry.title,
                                    style: TextStyle(
                                      fontSize:   14,
                                      fontWeight: FontWeight.w500,
                                      color: Color.lerp(
                                        cs.onSurface,
                                        cs.onSurface.withValues(alpha: 0.35),
                                        _strikeAnim.value,
                                      ),
                                      decoration: entry.isDone
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      decorationColor: cs.onSurface.withValues(alpha: 0.4),
                                      decorationThickness: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (entry.isNotified)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.notifications_active_rounded,
                                    size:  14,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                ),
                              SizedBox(
                                width:  24,
                                height: 24,
                                child: Checkbox(
                                  value:     entry.isDone,
                                  onChanged: (_) => notifier.toggleDone(entry.id),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // ── FIX 4: The Drop-down Details Panel (Reveals when tapped) ──
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(79, 0, 14, 14), // Inline alignment past the gutter line
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'Duration: ${_formatTimeString(entry.startTime)} - ${_formatTimeString(entry.endTime)}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
                              style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            // ── Future Edit Action Button Stub ──────────────
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                  showModalBottomSheet(
                                  context:            context,
                                  isScrollControlled: true,
                                  useSafeArea:        true,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  builder: (_) => UncontrolledProviderScope(
                                    container: ProviderScope.containerOf(context),
                                    child: _AddTaskSheet(initialEntry: entry), // PASSING DATA HERE
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit_rounded, size: 14),
                              label: const Text('Edit', style: TextStyle(fontSize: 12)),
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

  // String _formatHour(DateTime dt) =>
  //     '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}';

  // String _formatMinute(DateTime dt) =>
  //     '${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
}

// ════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ════════════════════════════════════════════════════════════════════════════

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
              color:      cs.onSurface.withValues(alpha: 0.4),
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

// ════════════════════════════════════════════════════════════════════════════
// ADD TASK SHEET
// ════════════════════════════════════════════════════════════════════════════

class _AddTaskSheet extends ConsumerStatefulWidget {
  // ── FIX 1: Add parameter to capture target item for edit workflows ───────
  final PlannerModel? initialEntry; 
  
  const _AddTaskSheet({this.initialEntry});

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  // Use late to safely coordinate constructor assignments inside initState
  late final TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();

  bool      _isSaving      = false;
  bool      _notifyMe      = false;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late RepeatInterval _repeatInterval;
  Duration?      _customInterval;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;

    // ── FIX 2: Check for existing task properties to hydrate the form ────────
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
        hour:   (_startTime.hour + 1) % 24,
        minute: _startTime.minute,
      );
      // Auto-focus text keyboard ONLY when framing an empty sheet
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _titleFocus.requestFocus(),
      );
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
      context:     context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        final startMins = picked.hour * 60 + picked.minute;
        final endMins   = _endTime.hour * 60 + _endTime.minute;
        if (endMins <= startMins) {
          final advanced = startMins + 60;
          _endTime = TimeOfDay(
            hour:   (advanced ~/ 60) % 24,
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
        title: const Text('Custom Interval', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Repeat every X days',
            hintText: 'e.g. 3',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

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
    if (_titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }
    setState(() => _isSaving = true);
    try {
      final day = ref.read(selectedDayProvider);

      DateTime toDateTime(TimeOfDay t) =>
          DateTime(day.year, day.month, day.day, t.hour, t.minute);

      final startDt = toDateTime(_startTime);
      final endDt   = toDateTime(_endTime);

      // ── FIX 3: Branch code paths dynamically between Edit and Create actions ──
      if (widget.initialEntry != null) {
        // Edit Mode: Update properties while retaining task ID key metrics
        final updatedEntry = widget.initialEntry!.copyWith(
          title:          _titleCtrl.text.trim(),
          startTime:      startDt,
          endTime:        endDt,
          isNotified:     _notifyMe,
          repeatInterval: _repeatInterval,
          customInterval: _customInterval,
        );
        ref.read(plannerProvider.notifier).updateEntry(updatedEntry);
      } else {
        // Create Mode: Establish new ID and push directly into list notifier
        final id = 'entry_${DateTime.now().millisecondsSinceEpoch}';
        final entry = PlannerModel(
          id:             id,
          title:          _titleCtrl.text.trim(),
          startTime:      startDt,
          endTime:        endDt,
          isNotified:     _notifyMe,
          repeatInterval: _repeatInterval,
          customInterval: _customInterval,
        );
        ref.read(plannerProvider.notifier).addEntry(entry);
      }

      if (_notifyMe) {
        unawaited(
          NotificationService.instance.scheduleNotification(
            id:            widget.initialEntry?.id.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode,
            title:         'Cheq Reminder',
            body:          _titleCtrl.text.trim(),
            scheduledTime: startDt,
          ),
        );
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  
  // Your widget build(BuildContext context) structure continues exactly the same underneath...
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width:  40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:        cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header row
              Row(
                children: [
                  Text('New Task',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width:  16,
                            height: 16,
                            child:  CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Title
              TextField(
                controller:         _titleCtrl,
                focusNode:          _titleFocus,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText:  'What do you need to do?',
                  hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.35)),
                  filled:         true,
                  fillColor:      cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:  BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // Start + End time pickers
              Row(
                children: [
                  Expanded(
                    child: _TimeTile(
                      label: 'Start',
                      time:  _startTime,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeTile(
                      label: 'End',
                      time:  _endTime,
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
                  color:        cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      size:  18,
                      color: _repeatInterval != RepeatInterval.none ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Text('Repeat', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
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
                          _customInterval = null; // Flush remnants out safely
                        }
                      },
                      items: RepeatInterval.values.map((val) {
                        String display = val.name.toUpperCase();
                        if (val == RepeatInterval.custom && _customInterval != null) {
                          display = '${_customInterval!.inDays} DAYS';
                        }
                        return DropdownMenuItem(
                          value: val,
                          child: Text(display, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // Notification toggle
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color:        cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _notifyMe
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      size:  18,
                      color: _notifyMe
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Text('Remind me',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Switch(
                      value:     _notifyMe,
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

// ════════════════════════════════════════════════════════════════════════════
// TIME TILE — reusable start/end time picker chip
// ════════════════════════════════════════════════════════════════════════════

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String       label;
  final TimeOfDay    time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            // Wrap in Flexible to safely handle horizontal layout stretching
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize:      10,
                      fontWeight:    FontWeight.w600,
                      letterSpacing: 0.5,
                      color:         cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  Text(
                    time.format(context),
                    maxLines: 1, // Enforces that the time string NEVER wraps to a second line
                    overflow: TextOverflow.clip, // Prevents truncation strings from rendering
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w700,
                      color:      cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ]
        ),
      ),
    );
  }
}