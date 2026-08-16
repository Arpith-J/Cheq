// lib/services/group_sync_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

// ---------------------------------------------------------------------------
// GroupSyncService — hybrid polling for 'Spaces' & shared group tasks (No FCM)
// ---------------------------------------------------------------------------
//
// Runs in two modes:
//  * Foreground  — triggered from the app-lifecycle resume handler and the
//                  `groupSyncProvider` notifier. Hydrates the local cache only.
//  * Background  — invoked from the Workmanager callback dispatcher on the
//                  'hourly-group-sync' periodic task. Hydrates the local cache,
//                  diffs freshly fetched tasks against the locally known set,
//                  and reports genuinely NEW tasks so the dispatcher can post a
//                  lightweight local notification (Phase 3 — still no FCM).
//
// The sync is deliberately fire-and-forget and offline-safe: it never blocks
// the UI, swallows every error, and relies on Firestore's built-in offline
// persistence as the local database — hydrating the local cache by reading the
// shared group task documents. The "seen" task-id set is kept in
// SharedPreferences so the background worker never notifies twice for the same
// task and can tell whether anything is new without a heavyweight DB.

/// A task freshly detected by the background worker that is relevant to the
/// user (explicitly assigned to them, or unassigned within one of their
/// groups). Consumed by the Workmanager dispatcher to fire a local notification.
class NewGroupTask {
  const NewGroupTask({
    required this.taskId,
    required this.title,
    required this.spaceName,
  });

  final String taskId;
  final String title;

  /// Display name of the group the task was found in.
  final String spaceName;
}

class GroupSyncService {
  GroupSyncService._();
  static final GroupSyncService instance = GroupSyncService._();

  /// SharedPreferences keys — keep the timestamp, UID cache and seen-task-id
  /// set scoped so the background isolate can resolve state without a restored
  /// auth session.
  static const String lastSyncAtKey = 'group_sync_last_ran_at';
  static const String cachedUidKey = 'group_sync_cached_uid';
  static const String knownTaskIdsKey = 'group_sync_known_task_ids';

  /// Persists the signed-in UID so the background worker can resolve the user
  /// even before FirebaseAuth restores its session inside the isolate.
  Future<void> cacheUid(String uid) async {
    try {
      if (uid.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cachedUidKey, uid);
    } catch (e) {
      debugPrint('Group sync UID cache failed: $e');
    }
  }

  /// Returns the locally recorded last-sync timestamp, or null when the worker
  /// has never run on this device.
  Future<DateTime?> readLastSyncAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastSyncAtKey);
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('Group sync timestamp read failed: $e');
      return null;
    }
  }

  /// Foreground sync entry point. Fetches the user's groups, hydrates the
  /// local offline cache with each group's shared tasks, updates the "seen"
  /// task-id set (so tasks the user already saw in-app are never re-reported by
  /// the worker), then records the sync timestamp. Returns the timestamp on
  /// success, or null when skipped/failed. Never notifies from the foreground.
  Future<DateTime?> syncGroupTasks() async {
    final result = await _runSync();
    return result.syncedAt;
  }

  /// Background entry point used by the Workmanager callback dispatcher.
  /// Returns the list of NEW group tasks found since the last run (empty when
  /// nothing is new, the user is offline, or the worker was skipped).
  Future<List<NewGroupTask>> syncFromBackground() async {
    final result = await _runSync();
    return result.newTasks;
  }

  // ── Shared sync pipeline ─────────────────────────────────────────────────

  Future<_SyncResult> _runSync() async {
    if (!await _ensureFirebase()) return const _SyncResult();
    final uid = await _resolveUid();
    if (uid == null) return const _SyncResult();

    final now = DateTime.now();
    try {
      // 1. Resolve every group this user belongs to. The collection schema is
      //    placeholder; a non-existent collection yields an empty snapshot
      //    rather than an error, so this is safe offline.
      final membershipSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('group_memberships')
          .get();

      // 2. Pull each group's display name + shared tasks. Reading them through
      //    Firestore hydrates the built-in offline cache ("update the local
      //    database" — the offline-first local store).
      final newTasks = <NewGroupTask>[];
      final allTaskIds = <String>{};
      var syncedGroups = 0;

      final prefs = await SharedPreferences.getInstance();
      final knownIds =
          (prefs.getStringList(knownTaskIdsKey) ?? const <String>[]).toSet();

      for (final doc in membershipSnap.docs) {
        final groupId = doc.id;
        if (groupId.isEmpty) continue;

        final spaceName = await _groupName(groupId);
        final tasksSnap = await _db
            .collection('groups')
            .doc(groupId)
            .collection('tasks')
            .get();

        for (final taskDoc in tasksSnap.docs) {
          final data = taskDoc.data();
          final taskId = taskDoc.id;
          if (taskId.isEmpty) continue;

          allTaskIds.add(taskId);

          // Skip tasks this device has already seen.
          if (knownIds.contains(taskId)) continue;

          // Only surface tasks meant for this user: explicitly assigned to
          // them, or unassigned (implicitly shared to every group member).
          final assignedTo = data['assignedTo'] as String?;
          if (assignedTo != null && assignedTo != uid) continue;

          newTasks.add(NewGroupTask(
            taskId: taskId,
            title: (data['title'] as String?)?.trim().isNotEmpty == true
                ? data['title'] as String
                : 'New task',
            spaceName: spaceName,
          ));
        }

        if (tasksSnap.docs.isNotEmpty) syncedGroups++;
      }

      // 3. Persist the full seen set + freshness timestamp in one go, so the
      //    next background run only reports genuinely new tasks.
      await prefs.setStringList(knownTaskIdsKey, allTaskIds.toList());
      await prefs.setString(lastSyncAtKey, now.toIso8601String());

      debugPrint('Group sync completed for $uid '
          '($syncedGroups groups, ${allTaskIds.length} tasks, '
          '${newTasks.length} new)');
      return _SyncResult(syncedAt: now, newTasks: newTasks);
    } catch (e) {
      debugPrint('Group sync failed: $e');
      return const _SyncResult();
    }
  }

  /// Fetches a group's display name, falling back to the group id when the
  /// document is missing or unnamed.
  Future<String> _groupName(String groupId) async {
    try {
      final snap = await _db.collection('groups').doc(groupId).get();
      final name = snap.data()?['name'];
      if (name is String && name.trim().isNotEmpty) return name;
    } catch (e) {
      debugPrint('Group name lookup failed for $groupId: $e');
    }
    return groupId;
  }

  // ── Internals ────────────────────────────────────────────────────────────

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Initializes Firebase on demand. A background isolate owns a fresh Dart
  /// heap, so `Firebase.apps` is always empty there — this MUST be awaited
  /// before any Firestore call made from a background entry point.
  Future<bool> _ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return true;
    } catch (e) {
      debugPrint('Group sync Firebase init failed: $e');
      return false;
    }
  }

  /// Resolves the current user's UID from the live auth session, or — when the
  /// session has not been restored yet (background isolates) — from the cached
  /// UID written by the foreground app on resume.
  Future<String?> _resolveUid() async {
    final live = _auth.currentUser?.uid;
    if (live != null && live.isNotEmpty) return live;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cachedUidKey);
      if (cached != null && cached.isNotEmpty) return cached;
      // Fallback: the native widgets already cache the UID for background taps.
      return prefs.getString('widget_user_uid');
    } catch (e) {
      debugPrint('Group sync UID resolution failed: $e');
      return null;
    }
  }
}

/// Result of one shared sync pass. [newTasks] is only consumed by the
/// background path (the dispatcher turns it into local notifications).
class _SyncResult {
  const _SyncResult({this.syncedAt, this.newTasks = const []});

  final DateTime? syncedAt;
  final List<NewGroupTask> newTasks;
}
