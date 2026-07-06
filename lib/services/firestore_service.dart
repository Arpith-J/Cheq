import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';
import '../screens/daily_planner_screen.dart';
import 'home_widget_service.dart';

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
        _processAndSyncWidgets(refreshedTasks);
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
          // 🌟 Wrap this in a nested try/catch so even if a widget sync fails, 
          // it won't crash the core save operation or freeze your UI sheet!
          _processAndSyncWidgets(currentTasks);
        } catch (widgetError) {
          debugPrint("⚠️ Background widget sync error: $widgetError");
        }
      }
    } catch (e) {
      debugPrint("Failed to save task to Firestore: $e");
    }
  }

  /// ❌ DELETE
  Future<void> deleteTask(String taskId) async {
    try {
      // 🌟 FIX: Extract numbers and force them into a safe 32-bit integer range
      final rawDigits = taskId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedInt = int.tryParse(rawDigits);
      
      final int stableNotificationId = parsedInt != null 
          ? (parsedInt % 2147483647) 
          : taskId.hashCode;
          
      // Cancel the notification using the safe 32-bit ID
      await NotificationService.instance.cancelNotification(stableNotificationId);
      
      // Proceed with Firestore deletion
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

  /// Unified clean evaluation loop to determine what belongs on today's interface
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
        
        // Include older tasks if they are still uncompleted
        if (taskDate.isBefore(today) && !entry.isDone) return true;
        
        // Drop any future upcoming days out of today's widget feed
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
}