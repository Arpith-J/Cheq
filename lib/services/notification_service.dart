// lib/services/notification_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/planner_model.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  // Group Reminder actionable buttons: 'Snooze' (re-fire in 15 minutes) and
  // 'Done' (acknowledge the shared reminder in Firestore). Both run entirely
  // in this background isolate and never touch the personal task coin economy.
  if (response.actionId == 'group_snooze') {
    await _handleGroupSnooze(response);
    return;
  }
  if (response.actionId == 'group_done') {
    await _handleGroupDone(response);
    return;
  }

  // Only the "Mark as complete" action needs background handling. A plain tap
  // on the notification (actionId == null) re-launches the app normally.
  if (response.actionId != 'mark_done') return;

  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final taskId = data['taskId'] as String?;
    final uid = data['uid'] as String?;
    if (taskId == null || taskId.isEmpty || uid == null || uid.isEmpty) return;

    // 1. IMMEDIATELY dismiss the notification from the Android status bar.
    //    This happens before any Firestore work so the banner disappears even
    //    if the network is slow or the database update later fails. Prefers the
    //    explicit `notificationId` baked into the payload, falling back to the
    //    stable id derived from the task id for notifications scheduled before
    //    the field was added (see FirestoreService.saveTasksBatch/deleteTask).
    //
    //    NOTE: the singleton's `_plugin` was never initialized in this isolate
    //    (each isolate owns its own heap), so cancellation goes through
    //    `cancelNotification`, which spins up a fresh plugin instance for the
    //    background callback dispatcher's platform channel.
    final int notificationId = (data['notificationId'] as num?)?.toInt() ??
        stableNotificationIdFromTask(taskId);
    await NotificationService.instance.cancelNotification(notificationId);

    // 2. Complete the task in Firestore (coins, permanent ledgers, isDone)
    //    and refresh the home screen widgets.
    await FirestoreService.completeTaskFromBackground(taskId, uid);
  } catch (e) {
    debugPrint("Notification background action failed: $e");
  }
}

/// 'Snooze' action for a Group Reminder: dismisses the current notification and
/// re-fires the exact same payload 15 minutes from now. The rescheduled copy
/// keeps the original actions, so the user can keep snoozing or finally mark
/// the reminder done. No Firestore writes happen here — the reminder's trigger
/// time is untouched so the Group Reminders list stays in sync.
Future<void> _handleGroupSnooze(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final reminderId = data['taskId'] as String? ?? '';
    final int notificationId = (data['notificationId'] as num?)?.toInt() ??
        groupReminderNotificationId(reminderId);

    // 1. IMMEDIATELY dismiss the current notification from the Android status
    //    bar before scheduling anything, so a slow reschedule can't double-show.
    await NotificationService.instance.cancelNotification(notificationId);

    // 2. Re-fire the same notification 15 minutes from now using the existing
    //    payload (title/body/spaceId/taskId are all preserved inside it).
    await NotificationService.instance.rescheduleFromBackground(
      id: notificationId,
      title: (data['title'] as String?) ?? 'Group Reminder',
      body: (data['body'] as String?) ?? '',
      scheduledTime: DateTime.now().add(const Duration(minutes: 15)),
      payload: payload,
    );
  } catch (e) {
    debugPrint("Group reminder snooze failed: $e");
  }
}

/// 'Done' action for a Group Reminder: acknowledges the shared reminder in
/// `spaces/{spaceId}/reminders/{reminderId}` from the background isolate and
/// dismisses the active notification. The acknowledgement is the exact same
/// `isDone` flip the Group Reminders list uses, so every member's device
/// reconciles its local alarms through the normal sync path.
Future<void> _handleGroupDone(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final spaceId = data['spaceId'] as String?;
    final reminderId = data['taskId'] as String?;
    if (spaceId == null || spaceId.isEmpty ||
        reminderId == null || reminderId.isEmpty) {
      return;
    }

    await FirestoreService.acknowledgeGroupReminderFromBackground(
        spaceId, reminderId);
  } catch (e) {
    debugPrint("Group reminder acknowledgement failed: $e");
  }
}

/// Derives the stable notification id for a planner task, matching the exact
/// derivation used when the notification is scheduled (add_task_sheet.dart and
/// FirestoreService.saveTasksBatch/saveAndCleanTasksBatch).
int stableNotificationIdFromTask(String taskId) {
  final rawDigits = taskId.replaceAll(RegExp(r'[^0-9]'), '');
  final parsedInt = int.tryParse(rawDigits);
  return parsedInt != null ? (parsedInt % 2147483647) : taskId.hashCode;
}

/// Derives the stable, non-negative local notification id for a group reminder.
/// Masking off the sign bit keeps the id safe for the native plugin while still
/// letting any reminder be overwritten or cancelled by id.
int groupReminderNotificationId(String reminderId) =>
    reminderId.hashCode & 0x7fffffff;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
    } catch (e) {
      debugPrint("Failed to get local timezone: $e");
      tz.setLocalLocation(tz.getLocation('Etc/UTC'));
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await Future.delayed(const Duration(milliseconds: 500));
      await androidPlugin.requestExactAlarmsPermission();
    }

    await _plugin.initialize(
      onDidReceiveNotificationResponse: notificationTapBackground,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notification'), // Ensure this exists
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    _initialized = true;
  }

  // ── EXISTING SPECIFIC TASK REMINDER ──
  /// Schedules a task/reminder notification to be fired by the OS at exactly
  /// [scheduledTime] — never earlier, never at creation time. The wall-clock
  /// [scheduledTime] is anchored into the device's local timezone via
  /// `tz.TZDateTime.from(..., tz.local)` and registered with
  /// `AndroidScheduleMode.exactAllowWhileIdle`, so a future `startTime` is
  /// locked to its exact moment and the system (not the app) wakes the device
  /// to post it. A [scheduledTime] already in the past is left to the OS to
  /// fire immediately — the correct behaviour for an overdue reminder.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    if (!_initialized) await initialize();

    // Personal task reminders and the daily briefing default to the
    // 'mark_done' action; Group Reminders pass their own Snooze/Done actions.
    final resolvedActions = actions ??
        const <AndroidNotificationAction>[
          AndroidNotificationAction('mark_done', 'Mark as complete'),
        ];

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cheq_planner_channel',
        'Daily Planner',
        channelDescription: 'Reminders for your daily planner tasks',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_notification',
        actions: resolvedActions,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: payload,
      // Anchors the reminder to the exact scheduled wall-clock time in the
      // device's local timezone so a future startTime can never fire early.
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Reschedules an existing notification from a background isolate, used by
  /// the Group Reminder 'Snooze' action. Each isolate owns a fresh heap, so a
  /// fresh plugin instance is initialized WITHOUT requesting any permissions
  /// (they were already granted in the foreground — a background isolate must
  /// never open the exact-alarm settings screen). The copy reuses the exact
  /// [payload] so a later 'Snooze'/'Done' tap resolves the same reminder.
  Future<void> rescheduleFromBackground({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      tz.initializeTimeZones();
      try {
        final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
      } catch (e) {
        debugPrint("Background timezone lookup failed: $e");
        tz.setLocalLocation(tz.getLocation('Etc/UTC'));
      }

      final isolatePlugin = FlutterLocalNotificationsPlugin();
      await isolatePlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notification'),
        ),
      );

      await isolatePlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: payload,
        scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'cheq_planner_channel',
            'Daily Planner',
            channelDescription: 'Reminders for your daily planner tasks',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notification',
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction('group_snooze', 'Snooze'),
              AndroidNotificationAction('group_done', 'Done'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint("Background reminder reschedule failed: $e");
    }
  }

  // ── NEW DAILY REPEATING BRIEFING ──
  Future<void> scheduleDailyBriefing({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, time.hour, time.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: id,                         
      title: title,                   
      body: body,                     
      scheduledDate: scheduledDate,   
      notificationDetails: const NotificationDetails( 
        android: AndroidNotificationDetails(
          'daily_briefing_channel',
          'Daily Briefings',
          channelDescription: 'Morning overviews and evening reviews',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notification',
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('mark_done', 'Mark as complete'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats every day at this time
    );
  }

  Future<void> cancelNotification(int id) async {
    if (_initialized) {
      await _plugin.cancel(id: id);
      return;
    }
    // Background isolate: this singleton's plugin was never initialized here
    // (each isolate has its own heap), so use a fresh instance. `cancel()` only
    // needs the platform channel, which the background callback dispatcher
    // registers before invoking the entry point.
    final isolatePlugin = FlutterLocalNotificationsPlugin();
    await isolatePlugin.cancel(id: id);
  }
  
  Future<void> cancelBriefing(int id) async => await _plugin.cancel(id: id);

  // ── GROUP REMINDER SYNC ──

  /// Reconciles the device's local alarms against the current group reminders
  /// list for [currentUserId] inside [spaceId]:
  ///  - a reminder assigned to the user (or to the whole group via
  ///    `assignedTo == null` or `assignedTo == 'Everyone'`) that is still
  ///    unacknowledged and triggers in the future is scheduled at the EXACT
  ///    trigger time (see [scheduleNotification]: `tz.TZDateTime.from`
  ///    + `exactAllowWhileIdle`) with the 'Snooze'/'Done' actions — never fired
  ///    early at sync time. Re-scheduling the same id overwrites any prior
  ///    alarm in place;
  ///  - any reminder that is acknowledged, already in the past, or delegated to
  ///    someone else has its alarm cancelled so ghost notifications can never
  ///    fire.
  ///
  /// The payload embeds everything the background isolate needs to act on the
  /// reminder later (`spaceId`, the reminder id, the uid, the exact
  /// notification id, plus the title/body so a snooze can re-fire it).
  ///
  /// Returns the notification ids actually scheduled so callers can cancel
  /// alarms left behind by reminders that were deleted outright (the id of a
  /// deleted reminder is no longer present in the list to cancel).
  Future<Set<int>> syncGroupRemindersToNativeAlarms(
    List<PlannerModel> reminders,
    String currentUserId, {
    required String spaceId,
  }) async {
    if (!_initialized) await initialize();

    const groupActions = <AndroidNotificationAction>[
      AndroidNotificationAction('group_snooze', 'Snooze'),
      AndroidNotificationAction('group_done', 'Done'),
    ];

    final now = DateTime.now();
    final scheduled = <int>{};

    for (final reminder in reminders) {
      final notificationId = groupReminderNotificationId(reminder.id);
      // Mirrors isGroupTaskRelevantTo: 'Everyone' and null both mean group-wide.
      final targetsCurrentUser = reminder.assignedTo == null ||
          reminder.assignedTo == currentUserId ||
          reminder.assignedTo == 'Everyone';
      final shouldSchedule = targetsCurrentUser &&
          !reminder.isDone &&
          reminder.startTime.isAfter(now);

      if (shouldSchedule) {
        await scheduleNotification(
          id: notificationId,
          title: 'Group Reminder',
          body: reminder.title,
          scheduledTime: reminder.startTime,
          actions: groupActions,
          payload: jsonEncode({
            'kind': 'group_reminder',
            'spaceId': spaceId,
            'taskId': reminder.id,
            'uid': currentUserId,
            'notificationId': notificationId,
            'title': 'Group Reminder',
            'body': reminder.title,
          }),
        );
        scheduled.add(notificationId);
      } else {
        await cancelNotification(notificationId);
      }
    }

    return scheduled;
  }
}