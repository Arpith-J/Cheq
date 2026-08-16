// lib/services/local_notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ---------------------------------------------------------------------------
// LocalNotificationService — instant device alerts (no FCM)
// ---------------------------------------------------------------------------
//
// Drives the immediate "new shared task" banners produced by the Phase 2/3
// background polling pipeline. This deliberately complements the scheduled
// [NotificationService] (task reminders + daily briefings): reminders use
// `zonedSchedule`, while this service posts simple fire-and-forget local
// notifications the moment the Workmanager worker detects a new group task.
//
// Each background isolate owns a fresh Dart heap, so the singleton's plugin
// instance is created (and initialized) on demand per execution. Permission
// dialogs are only requested from the foreground — inside a background isolate
// `requestPermissions` is disabled and Android 13+ is probed via
// `areNotificationsEnabled()` instead (the foreground boot path in
// NotificationService already granted POST_NOTIFICATIONS + exact alarms).

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  static const String _channelId = 'group_sync_channel';
  static const String _channelName = 'Space Updates';
  static const String _channelDescription = 'New tasks shared in your groups';
  static const String _icon = 'ic_stat_notification';

  FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _idCounter = 0;

  /// Initializes the plugin for Android and iOS, requesting notification and
  /// exact-alarm permissions on Android 13+ when [requestPermissions] is true
  /// (foreground only — a background isolate cannot present the system dialog).
  Future<void> initialize({bool requestPermissions = true}) async {
    if (_initialized) return;

    final plugin = FlutterLocalNotificationsPlugin();

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null && requestPermissions) {
      // Android 13+ requires the runtime POST_NOTIFICATIONS permission; exact
      // alarm permission keeps `zonedSchedule`/exact-style alerts reliable.
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
    }

    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    _plugin = plugin;
    _initialized = true;
  }

  /// Posts an immediate local notification. Never throws on permission issues:
  /// on Android 13+ where notifications are disabled the call is silently
  /// skipped instead of surfacing a platform error in the background worker.
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    await initialize(requestPermissions: false);

    // Android 13+: posting while permission is denied is a silent no-op on the
    // platform side, but probing first keeps the worker cheap and predictable.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled();
      if (enabled != true) return;
    }

    await _plugin.show(
      id: _nextId(),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Collision-safe positive notification id derived from the current time.
  /// Unique among the notifications posted within one execution (a background
  /// run starts a fresh singleton, so cross-run reuse is harmless).
  int _nextId() {
    final base = DateTime.now().millisecondsSinceEpoch & 0x3fffffff;
    return base + _idCounter++;
  }
}
