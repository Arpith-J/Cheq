// lib/services/background_sync_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'local_notification_service.dart';

// ---------------------------------------------------------------------------
// BackgroundSyncService — closed-app polling engine (no FCM)
// ---------------------------------------------------------------------------
//
// Phase 9 background engine. A Workmanager periodic task wakes a background
// isolate every 15 minutes, polls the user's Spaces for shared tasks/reminders
// that were created or modified since the last successful check, and posts a
// lightweight local notification for anything genuinely NEW that is assigned
// to the current user (or to 'Everyone').
//
// The background isolate is fully self-contained and fails gracefully:
//  * Firebase is initialized on demand inside the dispatcher — each isolate
//    owns a fresh Dart heap, so `Firebase.apps` is always empty there;
//  * the user is resolved from the live auth session, falling back to the UID
//    cached in SharedPreferences by the foreground app;
//  * the "last successful check" timestamp and the "seen item" set both live in
//    SharedPreferences, so a crashed or offline run can never re-notify;
//  * every failure is swallowed — no network, no auth, no permission => the
//    worker returns early and always reports completion to the OS.
//
// The first ever run on a device is treated as a baseline: every existing item
// is recorded WITHOUT notifying, so a fresh install never floods the user with
// notifications for history that predates the worker.

/// Type of shared item surfaced by the background worker.
enum NewGroupItemKind { task, reminder }

/// A shared item freshly detected by the background worker that is relevant to
/// the signed-in user. Consumed by [callbackDispatcher] to post notifications.
class NewGroupItem {
  const NewGroupItem({
    required this.kind,
    required this.title,
    required this.spaceName,
  });

  final NewGroupItemKind kind;

  /// Title of the task/reminder (fallback string when the doc has none).
  final String title;

  /// Display name of the Space the item was found in.
  final String spaceName;
}

/// Workmanager callback dispatcher — the single background entry point. Fires
/// in a background isolate whenever a scheduled task is due. Initializes
/// Firebase, polls every Space for new shared tasks/reminders and posts one
/// local notification per genuinely new item relevant to the user. Never
/// throws across the platform boundary: failures are logged and a completion
/// signal is always returned so the OS stops the worker cleanly.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final items = await BackgroundSyncService.instance.syncFromBackground();

      for (final item in items) {
        final isReminder = item.kind == NewGroupItemKind.reminder;
        await LocalNotificationService.instance.showNotification(
          title: isReminder
              ? 'New Reminder: ${item.title} in ${item.spaceName}'
              : 'New Task: ${item.title} in ${item.spaceName}',
          body: isReminder
              ? 'A group reminder was shared with you'
              : 'A group task was shared with you',
        );
      }

      debugPrint(
          'Workmanager [$task]: background sync found ${items.length} new item(s)');
      return true;
    } catch (e) {
      debugPrint('Workmanager [$task] background sync failed: $e');
      return false;
    }
  });
}

class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService instance = BackgroundSyncService._();

  /// SharedPreferences keys. The UID cache key intentionally matches the
  /// foreground writer (`GroupSyncService.cacheUid` boot path) so the worker can
  /// resolve the user even before FirebaseAuth restores its session in-isolate.
  static const String lastCheckAtKey = 'group_sync_last_check_at';
  static const String knownItemIdsKey = 'group_sync_known_item_ids';
  static const String cachedUidKey = 'group_sync_cached_uid';

  /// Persists the signed-in UID so the background worker can resolve the user
  /// even when FirebaseAuth hasn't restored its session in-isolate.
  Future<void> cacheUid(String uid) async {
    try {
      if (uid.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cachedUidKey, uid);
    } catch (e) {
      debugPrint('Background sync UID cache failed: $e');
    }
  }

  /// Background entry point used by [callbackDispatcher]. Polls every Space the
  /// user belongs to for shared tasks/reminders created or modified since the
  /// last successful check and returns the NEW items relevant to the user.
  ///
  /// The first ever run seeds the baseline silently (never notifies for
  /// history). Offline or failed runs return an empty list and leave the last
  /// check timestamp intact, so a later run still catches anything missed.
  Future<List<NewGroupItem>> syncFromBackground() async {
    if (!await _ensureFirebase()) return const [];
    final uid = await _resolveUid();
    if (uid == null) return const [];

    try {
      final prefs = await SharedPreferences.getInstance();

      // `since` is null on the first ever run -> the run becomes a baseline
      // (record everything, notify nothing) instead of a historical flood.
      final since = DateTime.tryParse(prefs.getString(lastCheckAtKey) ?? '');
      final knownIds =
          (prefs.getStringList(knownItemIdsKey) ?? const <String>[]).toSet();

      final result = await _collectNewItems(
        uid: uid,
        since: since,
        knownIds: knownIds,
      );

      // Persist the fresh "seen" set + timestamp in one go so the next run only
      // surfaces items that changed after this point.
      await prefs.setStringList(knownItemIdsKey, result.allItemIds.toList());
      await prefs.setString(
        lastCheckAtKey,
        DateTime.now().toIso8601String(),
      );

      debugPrint('Background sync completed for $uid '
          '(${result.allItemIds.length} known items, '
          '${result.newItems.length} new)');
      return result.newItems;
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return const [];
    }
  }

  // ── Sync pipeline ───────────────────────────────────────────────────────

  Future<_CollectResult> _collectNewItems({
    required String uid,
    required DateTime? since,
    required Set<String> knownIds,
  }) async {
    final newItems = <NewGroupItem>[];
    final allItemIds = <String>{...knownIds};

    // 1. Resolve every Space this user belongs to (matches the in-app
    //    `streamUserSpaces` query).
    final spacesSnap = await _db
        .collection('spaces')
        .where('members', arrayContains: uid)
        .get();

    // 2. Inspect the `tasks` and `reminders` subcollections of each Space.
    for (final spaceDoc in spacesSnap.docs) {
      final spaceId = spaceDoc.id;
      if (spaceId.isEmpty) continue;

      final spaceName = _spaceDisplayName(spaceDoc.data(), spaceId);

      await _inspectSubcollection(
        collection: _db
            .collection('spaces')
            .doc(spaceId)
            .collection('tasks'),
        uid: uid,
        spaceName: spaceName,
        kind: NewGroupItemKind.task,
        since: since,
        knownIds: knownIds,
        allItemIds: allItemIds,
        newItems: newItems,
      );
      await _inspectSubcollection(
        collection: _db
            .collection('spaces')
            .doc(spaceId)
            .collection('reminders'),
        uid: uid,
        spaceName: spaceName,
        kind: NewGroupItemKind.reminder,
        since: since,
        knownIds: knownIds,
        allItemIds: allItemIds,
        newItems: newItems,
      );
    }

    return _CollectResult(allItemIds: allItemIds, newItems: newItems);
  }

  Future<void> _inspectSubcollection({
    required CollectionReference<Map<String, dynamic>> collection,
    required String uid,
    required String spaceName,
    required NewGroupItemKind kind,
    required DateTime? since,
    required Set<String> knownIds,
    required Set<String> allItemIds,
    required List<NewGroupItem> newItems,
  }) async {
    final snap = await collection.get();

    for (final doc in snap.docs) {
      final itemId = doc.id;
      if (itemId.isEmpty) continue;

      final data = doc.data();
      allItemIds.add(itemId);

      // Baseline run (first ever): record ids, notify nothing.
      if (since == null) continue;

      // Only documents created or modified after the last successful check.
      final changedAt = _changedSinceSignal(data);
      if (changedAt == null || !changedAt.isAfter(since)) continue;

      // Only items aimed at the whole group or at this user ('Everyone' is
      // treated like a group-wide assignment).
      final assignedTo = data['assignedTo'] as String?;
      if (assignedTo != null &&
          assignedTo != uid &&
          assignedTo != 'Everyone') {
        continue;
      }

      // Never notify twice for the same item.
      if (knownIds.contains(itemId)) continue;

      final rawTitle = data['title'] as String?;
      newItems.add(NewGroupItem(
        kind: kind,
        title: (rawTitle != null && rawTitle.trim().isNotEmpty)
            ? rawTitle
            : (kind == NewGroupItemKind.task
                ? 'New group task'
                : 'New group reminder'),
        spaceName: spaceName,
      ));
    }
  }

  /// The newest "created/modified" timestamp recorded on a document. Supports
  /// ISO strings (this app's write path) and Firestore [Timestamp]s, tolerating
  /// documents that carry only `createdAt` or only `updatedAt`.
  DateTime? _changedSinceSignal(Map<String, dynamic> data) {
    final created = _timestamp(data['createdAt']);
    final updated = _timestamp(data['updatedAt']);
    if (created == null) return updated;
    if (updated == null) return created;
    return created.isAfter(updated) ? created : updated;
  }

  DateTime? _timestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _spaceDisplayName(Map<String, dynamic> data, String spaceId) {
    final name = data['name'];
    return (name is String && name.trim().isNotEmpty) ? name : spaceId;
  }

  // ── Internals ───────────────────────────────────────────────────────────

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
      debugPrint('Background sync Firebase init failed: $e');
      return false;
    }
  }

  /// Resolves the current user's UID from the live auth session, or — when the
  /// session has not been restored yet (background isolates) — from the cached
  /// UID written by the foreground app on boot/resume.
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
      debugPrint('Background sync UID resolution failed: $e');
      return null;
    }
  }
}

class _CollectResult {
  const _CollectResult({required this.allItemIds, required this.newItems});

  final Set<String> allItemIds;
  final List<NewGroupItem> newItems;
}
