// lib/providers/group_tasks_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';

// ---------------------------------------------------------------------------
// Group To-Do tasks — collaborative checklist state (Riverpod 3.0)
// ---------------------------------------------------------------------------

/// Live stream of the shared to-do checklist stored under
/// `spaces/{spaceId}/tasks`. Keyed by Space so each Space's Group To-Do tab
/// listens only to its own subcollection, and every member sees the same list
/// in near-real-time.
final groupTasksProvider =
    StreamProvider.family<List<PlannerModel>, String>((ref, spaceId) {
  return FirestoreService.instance.streamGroupTasks(spaceId);
});
