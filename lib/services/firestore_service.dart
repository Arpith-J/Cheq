import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';
import 'home_widget_service.dart';
import '../services/notification_service.dart';
import '../models/category_model.dart';


const String appName = String.fromEnvironment('APP_NAME', defaultValue: 'Cheq');
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
  /// Deletes a task ONLY when BOTH conditions hold:
  ///   a) the task is completed ('isDone == true')
  ///   b) its 'startTime' is before (now - 2 days)
  /// Pending tasks ('isDone == false') always bypass deletion, regardless of age.
  Future<void> runAutomaticDataCleanup(List<PlannerModel> allTasks) async {
    final ref = _plannerRef;
    if (ref == null) return;

    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 2));

      // Filter tasks to find completed ones strictly older than 2 days
      final tasksToDelete = allTasks.where((task) {
        return task.isDone == true && task.startTime.isBefore(cutoff);
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
      final ref = _plannerRef;
      if (ref == null) return;

      // Pull all THREE widget datasets back out of SharedPreferences.
      final todayJson =
          await HomeWidget.getWidgetData<String>(HomeWidgetService.todayDataKey);
      final plannerJson =
          await HomeWidget.getWidgetData<String>(HomeWidgetService.plannerDataKey);
      final todoJson =
          await HomeWidget.getWidgetData<String>(HomeWidgetService.todoDataKey);

      final List<dynamic> todayTasks =
          todayJson == null || todayJson.isEmpty ? [] : jsonDecode(todayJson) as List<dynamic>;
      final List<dynamic> plannerTasks =
          plannerJson == null || plannerJson.isEmpty ? [] : jsonDecode(plannerJson) as List<dynamic>;
      final List<dynamic> todoItems =
          todoJson == null || todoJson.isEmpty ? [] : jsonDecode(todoJson) as List<dynamic>;

      if (todayTasks.isEmpty && plannerTasks.isEmpty && todoItems.isEmpty) return;

      final snapshot = await ref.get();
      final currentTasks = snapshot.docs
          .map((doc) => PlannerModel.fromMap(doc.data()))
          .toList();

      final Map<String, PlannerModel> taskMap = {
        for (final task in currentTasks) task.id: task,
      };

      bool changedAnything = false;

      // Planner task toggles (rows overlap between the Today and Planner
      // widgets, so dedupe by task id before syncing).
      final seen = <String>{};
      for (final raw in [...todayTasks, ...plannerTasks]) {
        if (raw is! Map<String, dynamic>) continue;

        final String? taskId = raw['id'] as String?;
        final bool widgetDone = raw['isDone'] as bool? ?? false;

        if (taskId == null || !seen.add(taskId)) continue;

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

      // To-Do item toggles from the Todo widget.
      if (todoItems.isNotEmpty) {
        changedAnything =
            await _syncTodoWidgetChanges(todoItems) || changedAnything;
      }

      if (changedAnything) {
        final refreshed = await ref.get();
        final refreshedTasks = refreshed.docs
            .map((doc) => PlannerModel.fromMap(doc.data()))
            .toList();
            
        // Re-push clean data and trigger self-cleaning on status alterations
        _processAndSyncWidgets(refreshedTasks);
        unawaited(runAutomaticDataCleanup(refreshedTasks));
      }
    } catch (e) {
      debugPrint("Widget sync-back failed: $e");
    }
  }

  /// Compares the To-Do widget's rows against Firestore and applies any
  /// completions to the owning `todo_collections` document. Returns true when
  /// at least one collection was mutated.
  Future<bool> _syncTodoWidgetChanges(List<dynamic> widgetItems) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Group rows that were marked as done by their owning collection.
    final byCollection = <String, List<Map<String, dynamic>>>{};
    for (final raw in widgetItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (item['isDone'] != true) continue;

      final collectionId = item['collectionId'] as String?;
      final itemId = item['id'] as String?;
      if (collectionId == null || itemId == null) continue;

      byCollection.putIfAbsent(collectionId, () => []).add(item);
    }
    if (byCollection.isEmpty) return false;

    var changed = false;
    for (final entry in byCollection.entries) {
      final colRef = _db
          .collection('users')
          .doc(user.uid)
          .collection('todo_collections')
          .doc(entry.key);

      final colSnap = await colRef.get();
      if (!colSnap.exists) continue;

      final data = colSnap.data()!;
      final completedIds = entry.value.map((e) => e['id']).toSet();
      final rawItems = List<Map<String, dynamic>>.from(
        ((data['items'] as List<dynamic>?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final updated = rawItems.map((item) {
        if (completedIds.contains(item['id']) && item['isDone'] != true) {
          return {...item, 'isDone': true};
        }
        return item;
      }).toList();

      final didChange =
          rawItems.length != updated.length ||
          rawItems.any((a) {
            final b = updated[rawItems.indexOf(a)];
            return a['isDone'] != b['isDone'];
          });
      if (!didChange) continue;

      final allDone = updated.every((item) => item['isDone'] == true);
      final wasArchived = data['isArchived'] as bool? ?? false;
      final batch = _db.batch();
      batch.update(colRef, {'items': updated});
      if (allDone) {
        batch.update(colRef, {
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(),
        });
      } else if (wasArchived) {
        batch.update(colRef, {
          'isArchived': false,
          'archivedAt': FieldValue.delete(),
        });
      }
      await batch.commit();
      changed = true;
    }
    return changed;
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
      unawaited(_pushAllWidgetData(allTasks));
    } catch (e) {
      debugPrint("Widget processing engine sync failed: $e");
    }
  }

  /// Fire-and-forget push of the three widget datasets (Today, Planner, Todo).
  Future<void> _pushAllWidgetData(List<PlannerModel> allTasks) async {
    try {
      final todoItems = await _fetchActiveTodoItems();
      await HomeWidgetService.updateHomeScreenWidgets(
        tasks: allTasks,
        todoItems: todoItems,
      );
    } catch (e) {
      debugPrint("Widget processing engine sync failed: $e");
    }
  }

  /// Gathers every pending item (`isDone == false`) across all active
  /// (non-archived) `todo_collections`, shaped as widget rows.
  Future<List<Map<String, dynamic>>> _fetchActiveTodoItems() async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('todo_collections')
          .get();

      final items = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['isArchived'] == true) continue;

        final collectionTitle = data['title'] as String? ?? '';
        final rawItems = (data['items'] as List<dynamic>?) ?? const [];
        for (final raw in rawItems) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          if (item['isDone'] == true) continue;

          items.add({
            'id': item['id'],
            'title': item['text'] as String? ?? '',
            'isDone': false,
            'time': '',
            'date': collectionTitle,
            'collectionId': doc.id,
          });
        }
      }
      return items;
    } catch (e) {
      debugPrint("Failed to fetch todo items for widget: $e");
      return const [];
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
            title: '$appName Reminder',
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
            title: '$appName Reminder',
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

  // --- CATEGORY METHODS ---

  // 1. Get Categories Stream
  Stream<List<CategoryModel>> getUserCategories(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('categories')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CategoryModel.fromMap(doc.data()))
            .toList());
  }

  // 2. Add a Category
  Future<void> addCategory(String uid, CategoryModel category) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('categories')
        .doc(category.id)
        .set(category.toMap());
  }

  // 3. Delete a Category
  Future<void> deleteCategory(String uid, String categoryId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('categories')
        .doc(categoryId)
        .delete();
  }
}

// Helper utility for fire-and-forget background cleanup tasks
void unawaited(Future<void> future) {}