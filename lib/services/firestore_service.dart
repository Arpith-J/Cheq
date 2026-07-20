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

  /// AUTOMATIC 2-DAY CLEANUP CYCLE
  /// Finds all tasks marked as completed ('isDone == true') whose scheduled 
  /// date is older than 2 days relative to today and deletes them.
  Future<void> runAutomaticDataCleanup(List<PlannerModel> allTasks) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final now = DateTime.now();
      // Changed to 2 days
      final thresholdDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));

      // Filter tasks to find completed ones older than 2 days
      final tasksToDelete = allTasks.where((task) {
        final taskDate = DateTime(task.startTime.year, task.startTime.month, task.startTime.day);
        return task.isDone && taskDate.isBefore(thresholdDate);
      }).toList();

      if (tasksToDelete.isEmpty) return;

      final batch = _db.batch();
      
      for (final task in tasksToDelete) {
        batch.delete(ref.doc(task.id));
        
        // Clean up any lingering native notifications just in case
        final rawDigits = task.id.replaceAll(RegExp(r'[^0-9]'), '');
        final parsedInt = int.tryParse(rawDigits);
        if (parsedInt != null) {
          await NotificationService.instance.cancelNotification(parsedInt % 2147483647);
        }
      }

      await batch.commit();
      debugPrint("Background Cleanup: Purged ${tasksToDelete.length} old completed tasks.");
    } catch (e) {
      debugPrint("Background cleanup failed: $e");
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
          debugPrint("Background widget/cleanup error: $widgetError");
        }
      }
    } catch (e) {
      debugPrint("Failed to save task to Firestore: $e");
    }
  }

  /// DELETE
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
  /// 🌊 BATCH UPDATE FOR LIQUID RESCHEDULER
  Future<void> saveTasksBatch(List<PlannerModel> tasks) async {
    final ref = _plannerRef;
    if (ref == null || tasks.isEmpty) return;

    try {
      final batch = _db.batch();
      for (final task in tasks) {
        batch.set(ref.doc(task.id), task.toMap(), SetOptions(merge: true));
        
        // Update notification for the shifted task
        if (task.isNotified) {
          final rawDigits = task.id.replaceAll(RegExp(r'[^0-9]'), '');
          final parsedInt = int.tryParse(rawDigits);
          final int stableId = parsedInt != null ? (parsedInt % 2147483647) : task.id.hashCode;
          
          await NotificationService.instance.cancelNotification(stableId);
          unawaited(NotificationService.instance.scheduleNotification(
            id: stableId,
            title: 'Cheq Reminder',
            body: task.title,
            scheduledTime: task.startTime,
          ));
        }
      }
      await batch.commit();
      debugPrint("🌊 Liquid Rescheduler successfully batch updated ${tasks.length} tasks.");
    } catch (e) {
      debugPrint("Batch update failed: $e");
    }
  }
  /// 🧠 BATCH UPDATE FOR AI RESCHEDULER (HANDLES TASK SPLITTING)
  Future<void> saveAndCleanTasksBatch(List<PlannerModel> tasksToSave, List<String> taskIdsToDelete) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final batch = _db.batch();
      
      // 1. Delete original tasks that were split by the AI
      for (final id in taskIdsToDelete) {
        batch.delete(ref.doc(id));
        
        // Clean up old notifications
        final rawDigits = id.replaceAll(RegExp(r'[^0-9]'), '');
        final parsedInt = int.tryParse(rawDigits);
        if (parsedInt != null) {
          await NotificationService.instance.cancelNotification(parsedInt % 2147483647);
        }
      }

      // 2. Save shifted tasks and newly split parts
      for (final task in tasksToSave) {
        batch.set(ref.doc(task.id), task.toMap(), SetOptions(merge: true));
        
        if (task.isNotified) {
          final rawDigits = task.id.replaceAll(RegExp(r'[^0-9]'), '');
          final parsedInt = int.tryParse(rawDigits);
          final int stableId = parsedInt != null ? (parsedInt % 2147483647) : task.id.hashCode;
          
          await NotificationService.instance.cancelNotification(stableId);
          unawaited(NotificationService.instance.scheduleNotification(
            id: stableId,
            title: 'Cheq Reminder',
            body: task.title,
            scheduledTime: task.startTime,
          ));
        }
      }
      
      await batch.commit();
      debugPrint("🧠 AI Rescheduler: Saved ${tasksToSave.length} tasks, Deleted ${taskIdsToDelete.length} split originals.");
    } catch (e) {
      debugPrint("Batch update & clean failed: $e");
    }
  }

  /// ⏪ RESTORES PREVIOUS STATE IF USER HITS UNDO
  Future<void> undoAiReschedule({
    required List<PlannerModel> originalTasks,
    required List<String> newlyCreatedSplitIds,
  }) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final batch = _db.batch();

      // 1. Delete the fragments the AI just created
      for (final splitId in newlyCreatedSplitIds) {
        batch.delete(ref.doc(splitId));
      }

      // 2. Restore the original tasks exactly as they were
      for (final original in originalTasks) {
        batch.set(ref.doc(original.id), original.toMap(), SetOptions(merge: true));
      }

      await batch.commit();
      debugPrint("⏪ AI Reschedule Undone. Restored ${originalTasks.length} tasks.");
    } catch (e) {
      debugPrint("Undo failed: $e");
    }
  }
  
  /// 🗑️ DELETES A SPECIFIC TASK OR ALL FUTURE RECURRING TASKS
  Future<void> deleteRecurringTaskGroup(String groupId, DateTime fromDate) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final snapshot = await ref.where('repeatGroupId', isEqualTo: groupId).get();
      final batch = _db.batch();
      bool changed = false;

      for (var doc in snapshot.docs) {
        final taskStartTime = DateTime.parse(doc.data()['startTime']);
        
        // Only delete tasks that are scheduled FOR or AFTER the selected date
        if (!taskStartTime.isBefore(DateTime(fromDate.year, fromDate.month, fromDate.day))) {
          batch.delete(doc.reference);
          changed = true;
           // Clean up notifications for deleted tasks
          final rawDigits = doc.id.replaceAll(RegExp(r'[^0-9]'), '');
          final parsedInt = int.tryParse(rawDigits);
          final int stableId = parsedInt != null ? (parsedInt % 2147483647) : doc.id.hashCode;
          await NotificationService.instance.cancelNotification(stableId);
        }
      }

      if (changed) {
        await batch.commit();
        // Sync widgets after massive deletion
        final refreshed = await ref.get();
        final refreshedTasks = refreshed.docs.map((d) => PlannerModel.fromMap(d.data())).toList();
        _processAndSyncWidgets(refreshedTasks);
      }
    } catch (e) {
      debugPrint("Failed to delete recurring group: $e");
    }
  }
}

// Helper utility for fire-and-forget background cleanup tasks
void unawaited(Future<void> future) {}