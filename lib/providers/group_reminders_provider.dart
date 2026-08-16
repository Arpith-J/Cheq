// lib/providers/group_reminders_provider.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

// ---------------------------------------------------------------------------
// Group Reminders — shared timed alerts + native alarm reconciliation
// ---------------------------------------------------------------------------

/// Live stream of the shared reminders stored under
/// `spaces/{spaceId}/reminders`. Keyed by Space so each Space's Group
/// Reminders tab listens only to its own subcollection, and every member sees
/// the same list in near-real-time.
///
/// Every emission that materially matters to the signed-in user (new reminder
/// aimed at them, an acknowledgement, a time change, a deletion) reconciles the
/// device's native local alarms via
/// [NotificationService.syncGroupRemindersToNativeAlarms]. A per-Space
/// fingerprint guards the sync so unrelated snapshot changes (e.g. a reminder
/// aimed at another member) never aggressively re-schedule the device's alarms.
final groupRemindersProvider =
    StreamProvider.family<List<PlannerModel>, String>((ref, spaceId) async* {
  // Last reconciled state for this Space, remembered across stream emissions.
  String lastFingerprint = '';
  Set<int> lastScheduledIds = const {};

  await for (final reminders
      in FirestoreService.instance.streamGroupReminders(spaceId)) {
    // Signed-out or a still-restoring session: leave the native alarms alone.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      final fingerprint = _relevantFingerprint(reminders, uid);
      if (fingerprint != lastFingerprint) {
        lastFingerprint = fingerprint;

        final scheduledIds = await NotificationService.instance
            .syncGroupRemindersToNativeAlarms(reminders, uid,
                spaceId: spaceId);

        // Cancel alarms for reminders that vanished from this Space's list
        // (deleted outright) — the sync method can only cancel what it still
        // sees, so the previously scheduled ids we no longer schedule become
        // the ghosts.
        for (final staleId in lastScheduledIds.difference(scheduledIds)) {
          await NotificationService.instance.cancelNotification(staleId);
        }
        lastScheduledIds = scheduledIds;
      }
    }

    yield reminders;
  }
});

/// Compact fingerprint of the reminders that matter to [uid]: every
/// unacknowledged reminder assigned to them, to the whole group ('Everyone' or
/// null), folded into a stable string. Any change to this set
/// (new/removed/reassigned, ack, or trigger time) forces a resync; identical
/// fingerprints skip it entirely.
String _relevantFingerprint(List<PlannerModel> reminders, String uid) {
  final relevant = reminders
      .where((r) =>
          (r.assignedTo == null ||
              r.assignedTo == uid ||
              r.assignedTo == 'Everyone') &&
          !r.isDone)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  return relevant
      .map((r) =>
          '${r.id}|${r.startTime.millisecondsSinceEpoch}|${r.assignedTo ?? 'everyone'}')
      .join(';');
}
