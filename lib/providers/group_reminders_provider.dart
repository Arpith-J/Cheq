// lib/providers/group_reminders_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';

// ---------------------------------------------------------------------------
// Group Reminders — shared timed alerts (Riverpod 3.0)
// ---------------------------------------------------------------------------

/// Live stream of the shared reminders stored under
/// `spaces/{spaceId}/reminders`. Keyed by Space so each Space's Group
/// Reminders tab listens only to its own subcollection, and every member sees
/// the same list in near-real-time.
final groupRemindersProvider =
    StreamProvider.family<List<PlannerModel>, String>((ref, spaceId) {
  return FirestoreService.instance.streamGroupReminders(spaceId);
});
