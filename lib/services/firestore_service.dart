import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../firebase_options.dart';
import '../models/planner_model.dart';
import '../models/user_model.dart';
import '../providers/rewards_provider.dart';
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

  Stream<List<PlannerModel>> streamPlannerEntries([String? uid]) {
    final user = _auth.currentUser;
    final resolvedUid = uid ?? user?.uid;
    if (resolvedUid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(resolvedUid)
        .collection('planner')
        .snapshots()
        .map((snapshot) {
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

  void _processAndSyncWidgets(List<PlannerModel> allTasks, {String? uid}) {
    try {
      unawaited(_pushAllWidgetData(allTasks, uid: uid));
    } catch (e) {
      debugPrint("Widget processing engine sync failed: $e");
    }
  }

  /// Fire-and-forget push of the three widget datasets (Today, Planner, Todo).
  Future<void> _pushAllWidgetData(List<PlannerModel> allTasks, {String? uid}) async {
    try {
      final resolvedUid = uid ?? _auth.currentUser?.uid;
      final todoItems = await _fetchActiveTodoItems(resolvedUid);

      // Cache the uid for the native widgets so a background checkbox tap can
      // build a `cheqwidget://mark_done` intent without FirebaseAuth state.
      if (resolvedUid != null && resolvedUid.isNotEmpty) {
        try {
          await HomeWidget.saveWidgetData('widget_user_uid', resolvedUid);
        } catch (e) {
          debugPrint("Widget UID cache failed: $e");
        }
      }

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
  /// Accepts an optional [uid] so the native background isolate can fetch rows
  /// even when `FirebaseAuth.currentUser` has not been restored yet.
  Future<List<Map<String, dynamic>>> _fetchActiveTodoItems([String? uid]) async {
    final user = _auth.currentUser;
    final resolvedUid = uid ?? user?.uid;
    if (resolvedUid == null) return const [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(resolvedUid)
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

  /// Explicit one-shot fetch of the user's economy document (`users/{uid}`).
  /// Used by the boot/login hydration path so coins, streaks, badges,
  /// constellation and the permanent stats ledgers are rendered from cloud
  /// truth immediately after a fresh install instead of showing 0.
  Future<UserModel?> getUserModel(String uid) async {
    try {
      final snapshot = await _userDocRef(uid).get();
      if (!snapshot.exists || snapshot.data() == null) return null;
      return UserModel.fromMap(snapshot.data()! as Map<String, dynamic>);
    } catch (e) {
      debugPrint("Failed to fetch user model from Firestore: $e");
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
            payload: jsonEncode({'taskId': task.id, 'uid': _auth.currentUser?.uid}),
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
            payload: jsonEncode({'taskId': task.id, 'uid': _auth.currentUser?.uid}),
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

// ── UNIFIED BACKGROUND COMPLETION ENGINE ────────────────────────────────
// Shared by actionable notification buttons and interactive home screen
// widgets. Mirrors `RewardsNotifier.awardPlannerTaskCompletion` so tasks
// completed off-app bank identical coins, badges and permanent stats ledgers.

/// Entry point invoked by the home screen widgets when a checkbox is tapped.
/// The tapped row is encoded as `cheqwidget://mark_done?taskId=<id>&uid=<uid>`.
@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null || uri.host != 'mark_done') return;

  final taskId = uri.queryParameters['taskId'];
  final uid = uri.queryParameters['uid'];
  if (taskId == null || taskId.isEmpty || uid == null || uid.isEmpty) return;

  await completeTaskFromBackground(taskId, uid);
}

/// Completes a planner task exactly like the in-app checkbox: persists
/// `isDone`/`isRewarded`/`coinsAwarded`, awards the coin reward (+ deep-work
/// bonus when the task runs >= 2 hours), unlocks badges (Night Owl when it
/// ends at/after 10 PM), and banks the real duration into the permanent stats
/// ledgers. Safe to call from a background isolate: Firebase is initialized on
/// demand and the widget refresh is keyed off the explicit [uid].
Future<void> completeTaskFromBackground(String taskId, String uid) async {
  if (taskId.isEmpty || uid.isEmpty) return;

  // A background isolate has its own Dart heap, so Firebase.apps is always
  // empty here. Initialize (and await) BEFORE any Firestore call is made.
  if (!await _ensureBackgroundFirebase()) return;

  try {
    final db = FirebaseFirestore.instance;
    final taskRef = db
        .collection('users')
        .doc(uid)
        .collection('planner')
        .doc(taskId);

    final taskSnap = await taskRef.get();
    if (!taskSnap.exists) return;

    final data = taskSnap.data();
    if (data == null || data['isDone'] == true) return;

    final startTime = DateTime.parse(data['startTime'] as String);
    final endTime = DateTime.parse(data['endTime'] as String);

    final minutes = _safeTaskMinutes(startTime, endTime);
    final category = (data['categoryName'] as String?) ?? 'Uncategorized';

    final reward =
        plannerBaseCoins + (minutes >= 120 ? plannerDeepWorkBonusCoins : 0);
    final badges = <String>[
      if (endTime.hour >= 22) nightOwlBadge,
    ];

    // Atomic: the task flips to done at the same instant the user's economy
    // and permanent stats ledgers are incremented.
    final batch = db.batch();
    batch.update(taskRef, {
      'isDone': true,
      'isRewarded': true,
      'coinsAwarded': reward,
    });

    batch.update(db.collection('users').doc(uid), {
      'coins': FieldValue.increment(reward),
      'totalMinutesLogged': FieldValue.increment(minutes),
      'categoryMinutes.$category': FieldValue.increment(minutes),
      'dailyMinutesLog.${_ledgerDateKey(startTime)}':
          FieldValue.increment(minutes),
      'dailyActivityLog.${_ledgerDateKey(DateTime.now())}':
          FieldValue.increment(1),
      if (badges.isNotEmpty) 'unlockedBadges': FieldValue.arrayUnion(badges),
    });

    await batch.commit();
    debugPrint(
        "Background completion: $taskId (+$reward coins, +$minutes min)");

    // Mirror the in-app checkbox flow (`task_row.dart` ->
    // `checkAndAwardPerfectDay`): when every task on the day is now done,
    // award the +50 Perfect Day bonus and bump the streak.
    await _maybeAwardPerfectDay(db, uid);

    // Explicitly trigger the Android widget update channel so the completed
    // task is instantly removed from the home screen. The datasets are rebuilt
    // from Firestore (not the pre-commit cache) so `isDone: true` is already
    // reflected before the SharedPreferences payloads are written.
    try {
      final snapshot = await db
          .collection('users')
          .doc(uid)
          .collection('planner')
          .get();
      final allTasks = snapshot.docs
          .map((doc) => PlannerModel.fromMap(doc.data()))
          .toList();

      // `_pushAllWidgetData` writes every dataset via HomeWidget.saveWidgetData
      // and calls HomeWidget.updateWidget for all three providers, then a final
      // direct channel trigger guarantees the primary task widget repaints.
      await FirestoreService.instance._pushAllWidgetData(allTasks, uid: uid);
      await HomeWidget.updateWidget(
        name: 'DailyTaskWidgetProvider',
        androidName: 'DailyTaskWidgetProvider',
      );
    } catch (e) {
      debugPrint("Background widget refresh failed: $e");
    }
  } catch (e) {
    debugPrint("Background completion failed for $taskId: $e");
  }
}

/// Initializes Firebase in a background isolate on demand. Each isolate owns a
/// fresh Dart heap, so `Firebase.apps` is always empty here — this MUST be
/// awaited before any Firestore call made from a background entry point.
Future<bool> _ensureBackgroundFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    return true;
  } catch (e) {
    debugPrint("Background Firebase init failed: $e");
    return false;
  }
}

/// Mirrors `RewardsNotifier.checkAndAwardPerfectDay` for completions that
/// happen off-app. When every task scheduled for the day (plus any pending
/// carry-over from earlier days) is done, awards the +50 Perfect Day bonus and
/// bumps the streak. Idempotent via `lastPerfectDay`, so racing the in-app
/// checkbox is safe.
Future<void> _maybeAwardPerfectDay(
  FirebaseFirestore db,
  String uid,
) async {
  try {
    final userRef = db.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data();
    if (userData == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lastPerfect = userData['lastPerfectDay'];
    if (lastPerfect is Timestamp &&
        lastPerfect.toDate().year == today.year &&
        lastPerfect.toDate().month == today.month &&
        lastPerfect.toDate().day == today.day) {
      return;
    }

    final snapshot = await db
        .collection('users')
        .doc(uid)
        .collection('planner')
        .get();

    // Mirrors `selectedDayEntriesProvider` for "today": today's tasks plus
    // pending tasks carried over from earlier days.
    final todaysTasks = snapshot.docs
        .map((doc) => PlannerModel.fromMap(doc.data()))
        .where((task) {
          final taskDay =
              DateTime(task.startTime.year, task.startTime.month, task.startTime.day);
          return taskDay == today || (taskDay.isBefore(today) && !task.isDone);
        })
        .toList();

    if (todaysTasks.isEmpty || !todaysTasks.every((task) => task.isDone)) {
      return;
    }

    await userRef.set({
      'coins': FieldValue.increment(perfectDayBonusCoins),
      'streakCount': FieldValue.increment(1),
      'lastPerfectDay': Timestamp.fromDate(today),
    }, SetOptions(merge: true));
    debugPrint(
        "Background Perfect Day awarded: +$perfectDayBonusCoins coins, +1 streak");
  } catch (e) {
    debugPrint("Background Perfect Day check failed: $e");
  }
}

/// Mirrors the rewards engine's safe-duration math: an end time before the
/// start time rolls into the next day, and a negative remainder clamps to 0.
int _safeTaskMinutes(DateTime startTime, DateTime endTime) {
  final safeEndTime = endTime.isBefore(startTime)
      ? endTime.add(const Duration(days: 1))
      : endTime;
  final rawMinutes = safeEndTime.difference(startTime).inMinutes;
  return rawMinutes < 0 ? 0 : rawMinutes;
}

/// Formats a date as a 'YYYY-MM-DD' ledger key (matches the in-app ledgers).
String _ledgerDateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}