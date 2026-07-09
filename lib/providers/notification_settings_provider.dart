// lib/providers/notification_settings_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';

class NotificationConfig {
  final bool morningEnabled;
  final TimeOfDay morningTime;
  final bool eveningEnabled;
  final TimeOfDay eveningTime;
  final bool showTaskBadges;

  const NotificationConfig({
    this.morningEnabled = false,
    this.morningTime = const TimeOfDay(hour: 8, minute: 0), // Default 8:00 AM
    this.eveningEnabled = false,
    this.eveningTime = const TimeOfDay(hour: 20, minute: 0), // Default 8:00 PM
    this.showTaskBadges = true,
  });

  NotificationConfig copyWith({
    bool? morningEnabled,
    TimeOfDay? morningTime,
    bool? eveningEnabled,
    TimeOfDay? eveningTime,
    bool? showTaskBadges,
  }) {
    return NotificationConfig(
      morningEnabled: morningEnabled ?? this.morningEnabled,
      morningTime: morningTime ?? this.morningTime,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      eveningTime: eveningTime ?? this.eveningTime,
      showTaskBadges: showTaskBadges ?? this.showTaskBadges,
    );
  }
}

class NotificationSettingsNotifier extends Notifier<NotificationConfig> {
  // Use stable IDs so we don't accidentally create duplicates
  static const int morningNotificationId = 100;
  static const int eveningNotificationId = 200;

  @override
  NotificationConfig build() {
    return const NotificationConfig();
  }

  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName?.split(' ').first ?? 'User';
  }

  String _getSalutation(TimeOfDay time) {
    if (time.hour >= 0 && time.hour < 12) return "morning";
    if (time.hour >= 12 && time.hour < 17) return "afternoon";
    if (time.hour >= 17 && time.hour < 21) return "evening";
    return "night";
  }

  // 🌅 MORNING LOGIC
  void toggleMorning(bool isEnabled) {
    state = state.copyWith(morningEnabled: isEnabled);
    if (isEnabled) {
      _rescheduleMorning(0);
    } else {
      NotificationService.instance.cancelBriefing(morningNotificationId);
    }
    _saveToFirebase(state);
  }

  void updateMorningTime(TimeOfDay time) {
    state = state.copyWith(morningTime: time);
    if (state.morningEnabled) _rescheduleMorning(0);
    _saveToFirebase(state);
  }

  void _rescheduleMorning(int taskCount) {
    final taskString = taskCount == 1 ? "1 task" : "$taskCount tasks";
    NotificationService.instance.scheduleDailyBriefing(
      id: morningNotificationId,
      time: state.morningTime,
      title: 'Moon Overview',
      body: 'Good ${_getSalutation(state.morningTime)} ${_getFirstName()}, you have $taskString scheduled for today.',
    );
  }

  // 🌃 EVENING LOGIC
  void toggleEvening(bool isEnabled) {
    state = state.copyWith(eveningEnabled: isEnabled);
    if (isEnabled) {
      _rescheduleEvening(0);
    } else {
      NotificationService.instance.cancelBriefing(eveningNotificationId);
    }
    _saveToFirebase(state);
  }

  void updateEveningTime(TimeOfDay time) {
    state = state.copyWith(eveningTime: time);
    if (state.eveningEnabled) _rescheduleEvening(0);
    _saveToFirebase(state);
  }
  
  void toggleTaskBadges(bool isEnabled) {
    state = state.copyWith(showTaskBadges: isEnabled);
    _saveToFirebase(state);
  }

  void _rescheduleEvening(int tasksLeft) {
    final taskString = tasksLeft == 1 ? "1 task" : "$tasksLeft tasks";
    final body = tasksLeft == 0 
        ? 'Good ${_getSalutation(state.eveningTime)} ${_getFirstName()}, you completed everything today! Great job.'
        : 'Good ${_getSalutation(state.eveningTime)} ${_getFirstName()}, you have $taskString left to finish today.';
    NotificationService.instance.scheduleDailyBriefing(
      id: eveningNotificationId,
      time: state.eveningTime,
      title: 'Moon Review',
      body: body,
    );
  }

  void syncBriefingPayloads(int totalTasksToday, int pendingTasksToday) {
    if (state.morningEnabled) _rescheduleMorning(totalTasksToday);
    if (state.eveningEnabled) _rescheduleEvening(pendingTasksToday);
  }

  void _saveToFirebase(NotificationConfig config) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Format TimeOfDay to a clean string "HH:MM" for the database
      String formatTime(TimeOfDay t) => 
          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

      FirestoreService.instance.saveUserSettings(uid, {
        'morningEnabled': config.morningEnabled,
        'morningTime': formatTime(config.morningTime),
        'eveningEnabled': config.eveningEnabled,
        'eveningTime': formatTime(config.eveningTime),
        'showTaskBadges': config.showTaskBadges,
      });
    }
  }
  Future<void> loadSettings(String uid) async {
      final settings = await FirestoreService.instance.getUserSettings(uid);
      if (settings != null) {
        
        // Helper to convert "08:00" string back into TimeOfDay
        TimeOfDay parseTime(String? timeStr, TimeOfDay defaultTime) {
          if (timeStr == null) return defaultTime;
          final parts = timeStr.split(':');
          if (parts.length == 2) {
            return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
          return defaultTime;
        }

        state = state.copyWith(
          morningEnabled: settings['morningEnabled'] as bool? ?? state.morningEnabled,
          morningTime: parseTime(settings['morningTime'] as String?, state.morningTime),
          eveningEnabled: settings['eveningEnabled'] as bool? ?? state.eveningEnabled,
          eveningTime: parseTime(settings['eveningTime'] as String?, state.eveningTime),
          showTaskBadges: settings['showTaskBadges'] as bool? ?? state.showTaskBadges,
        );
      }
    }
}

final notificationSettingsProvider = NotifierProvider<NotificationSettingsNotifier, NotificationConfig>(
  NotificationSettingsNotifier.new,
);