// lib/providers/space_members_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/space_model.dart';
import '../services/firestore_service.dart';
import 'spaces_provider.dart';

// ---------------------------------------------------------------------------
// Space members — display-name resolution for the 'Assign To' picker
// ---------------------------------------------------------------------------

/// Maps a Space's member UIDs to their display names, keyed by UID. Watched by
/// the Group Planner so scheduled tasks can be assigned to any member and every
/// assignee chip renders a human-readable name instead of a raw UID.
///
/// The underlying [userSpacesProvider] stream makes this reactive to membership
/// changes, and [FirestoreService.fetchUserDisplayNames] degrades gracefully to
/// short UID prefixes for members without a profile document.
final spaceMembersProvider =
    FutureProvider.family<Map<String, String>, String>((ref, spaceId) async {
  if (spaceId.isEmpty) return const {};

  final spaces = ref.watch(userSpacesProvider).value ?? const <SpaceModel>[];
  SpaceModel? space;
  for (final candidate in spaces) {
    if (candidate.id == spaceId) {
      space = candidate;
      break;
    }
  }

  return FirestoreService.instance
      .fetchUserDisplayNames(space?.members ?? const []);
});
