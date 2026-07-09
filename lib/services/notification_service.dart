// lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

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
        android: AndroidInitializationSettings('@drawable/ic_stat_notification'), // Ensure this exists
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
        icon: '@drawable/ic_stat_notification',
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
          icon: '@drawable/ic_stat_notification',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats every day at this time
    );
  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id: id);
  
  Future<void> cancelBriefing(int id) async => await _plugin.cancel(id: id);
}