import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';
import 'home_widget_service.dart';
import '../services/notification_service.dart';

class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? get _plannerRef {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _db.collection('users').doc(user.uid).collection('planner');
  }

  /// 🧹 AUTOMATIC 3-DAY CLEANUP CYCLE
  /// Finds all tasks marked as completed ('isDone == true') whose scheduled 
  /// date is older than 3 days relative to today and deletes them.
  Future<void> runAutomaticDataCleanup(List<PlannerModel> allTasks) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final now = DateTime.now();
      final thresholdDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 3));

      // Filter tasks to find completed tasks that scheduled 3+ days before today
      final tasksToPurge = allTasks.where((task) {
        if (!task.isDone) return false;
        final taskDate = DateTime(task.startTime.year, task.startTime.month, task.startTime.day);
        return taskDate.isBefore(thresholdDate);
      }).toList();

      if (tasksToPurge.isEmpty) return;

      debugPrint("🧹 Found ${tasksToPurge.length} completed tasks older than 3 days. Initiating cleanup...");

      // Execute batches/deletions in parallel safely
      await Future.wait(tasksToPurge.map((task) async {
        // Cancel notification structures
        final rawDigits = task.id.replaceAll(RegExp(r'[^0-9]'), '');
        final parsedInt = int.tryParse(rawDigits);
        final int stableNotificationId = parsedInt != null 
            ? (parsedInt % 2147483647) 
            : task.id.hashCode;

        await NotificationService.instance.cancelNotification(stableNotificationId);
        
        // Delete from Firestore database
        await ref.doc(task.id).delete();
        debugPrint("🗑️ Purged task: '${task.title}' (Scheduled: ${task.startTime})");
      }));

    } catch (e) {
      debugPrint("⚠️ Automatic 3-day cleanup routine encountered an error: $e");
    }
  }

  Future<void> syncWidgetChangesToFirestore() async {
    try {
      final String? tasksJson =
          await HomeWidget.getWidgetData<String>('flutter.daily_tasks_key');

      if (tasksJson == null || tasksJson.isEmpty) return;

      final List<dynamic> widgetTasks = jsonDecode(tasksJson);
      final ref = _plannerRef;
      if (ref == null) return;

      final snapshot = await ref.get();
      final currentTasks = snapshot.docs
          .map((doc) => PlannerModel.fromMap(doc.data()))
          .toList();

      final Map<String, PlannerModel> taskMap = {
        for (final task in currentTasks) task.id: task,
      };

      bool changedAnything = false;

      for (final raw in widgetTasks) {
        if (raw is! Map<String, dynamic>) continue;

        final String? taskId = raw['id'] as String?;
        final bool widgetDone = raw['isDone'] as bool? ?? false;

        if (taskId == null) continue;

        final existing = taskMap[taskId];
        if (existing == null) continue;

        if (existing.isDone != widgetDone) {
          await ref.doc(taskId).set(
            existing.copyWith(isDone: widgetDone).toMap(),
            SetOptions(merge: true),
          );
          changedAnything = true;
        }
      }

      if (changedAnything) {
        final refreshed = await ref.get();
        final refreshedTasks = refreshed.docs
            .map((doc) => PlannerModel.fromMap(doc.data()))
            .toList();
            
        // Trigger self-cleaning on status alterations
        _processAndSyncWidgets(refreshedTasks);
        unawaited(runAutomaticDataCleanup(refreshedTasks));
      }
    } catch (e) {
      debugPrint("Widget sync-back failed: $e");
    }
  }

  Stream<List<PlannerModel>> streamPlannerEntries() {
    final ref = _plannerRef;
    if (ref == null) return Stream.value([]);

    return ref.snapshots().map((snapshot) {
      final List<PlannerModel> entries = snapshot.docs.map((doc) {
        return PlannerModel.fromMap(doc.data());
      }).toList();
            
      _processAndSyncWidgets(entries);
      
      // Auto-runs cleanup silenty without blocking standard UI stream deliveries
      runAutomaticDataCleanup(entries);
      
      return entries;
    });
  }

  /// ➕ CREATE / UPDATE
  Future<void> saveTask(PlannerModel task) async {
    try {
      await _plannerRef?.doc(task.id).set(task.toMap(), SetOptions(merge: true));
      
      final snapshot = await _plannerRef?.get();
      if (snapshot != null) {
        final currentTasks = snapshot.docs.map((doc) => PlannerModel.fromMap(doc.data())).toList();
        
        try {
          _processAndSyncWidgets(currentTasks);
          // Run cleanup in parallel to save cycles
          runAutomaticDataCleanup(currentTasks);
        } catch (widgetError) {
          debugPrint("⚠️ Background widget/cleanup error: $widgetError");
        }
      }
    } catch (e) {
      debugPrint("Failed to save task to Firestore: $e");
    }
  }

  /// ❌ DELETE
  Future<void> deleteTask(String taskId) async {
    try {
      final rawDigits = taskId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedInt = int.tryParse(rawDigits);
      
      final int stableNotificationId = parsedInt != null 
          ? (parsedInt % 2147483647) 
          : taskId.hashCode;
          
      await NotificationService.instance.cancelNotification(stableNotificationId);
      await _plannerRef?.doc(taskId).delete();
      
      final snapshot = await _plannerRef?.get();
      if (snapshot != null) {
        final currentTasks = snapshot.docs.map((doc) => PlannerModel.fromMap(doc.data())).toList();
        _processAndSyncWidgets(currentTasks);
      }
    } catch (e) {
      debugPrint("Failed to delete task from Firestore: $e");
    }
  }

  void _processAndSyncWidgets(List<PlannerModel> allTasks) {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final todaysTasks = allTasks.where((entry) {
        final taskDate = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);
        
        final isToday = taskDate.year == today.year &&
                        taskDate.month == today.month &&
                        taskDate.day == today.day;

        if (isToday) return true;
        if (taskDate.isBefore(today) && !entry.isDone) return true;
        if (taskDate.isAfter(today)) return false;

        switch (entry.repeatInterval) {
          case RepeatInterval.none: return false;
          case RepeatInterval.daily: return true;
          case RepeatInterval.weekly: return entry.startTime.weekday == today.weekday;
          case RepeatInterval.monthly: return entry.startTime.day == today.day;
          case RepeatInterval.custom:
            if (entry.customInterval == null) return false;
            final difference = today.difference(taskDate).inDays;
            final stepInDays = entry.customInterval!.inDays;
            return stepInDays > 0 && (difference % stepInDays == 0);
        }
      }).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      HomeWidgetService.updateHomeScreenWidgetData(todaysTasks);
    } catch (e) {
      debugPrint("Widget processing engine sync failed: $e");
    }
  }

  DocumentReference _userDocRef(String uid) {
    return _db.collection('users').doc(uid);
  }

  Future<Map<String, dynamic>?> getUserSettings(String uid) async {
    try {
      final snapshot = await _userDocRef(uid).get();
      if (snapshot.exists && snapshot.data() != null) {
        return snapshot.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint("Failed to fetch user settings from Firestore: $e");
      return null;
    }
  }

  Future<void> saveUserSettings(String uid, Map<String, dynamic> settingsData) async {
    try {
      await _userDocRef(uid).set(settingsData, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to save user settings to Firestore: $e");
    }
  }
}

// Helper utility for fire-and-forget background cleanup tasks
void unawaited(Future<void> future) {}