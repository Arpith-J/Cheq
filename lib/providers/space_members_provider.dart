// lib/providers/space_members_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/space_model.dart';
import '../services/firestore_service.dart';
import 'spaces_provider.dart';

// ---------------------------------------------------------------------------
// Space members — live display-name resolution for the Spaces UI
// ---------------------------------------------------------------------------

/// Maps a Space's member UIDs to their display names, keyed by UID. Watched by
/// the Group Planner, the Group To-Do/Reminders sheets and the details sheet so
/// every assignee chip and roster row renders a human-readable name instead of
/// a raw UID.
///
/// Implemented as a [StreamProvider] (Riverpod 3.0) rather than a one-shot
/// FutureProvider:
///  * It watches [userSpacesProvider], so any roster change (join/leave/space
///    edit) tears down and rebuilds the stream automatically.
///  * The underlying [FirestoreService.streamUserDisplayNames] re-fetches the
///    `users/{uid}` profile documents while listened, so when another member
///    opens the app and force-writes their `displayName` via
///    `ensureDisplayName`, every device converges to real names within
///    seconds — even if the Space document itself never changed.
///
/// Bulletproofing contract — this provider can NEVER surface an error state:
///  * Every individual `users/{uid}` profile read is isolated inside its own
///    strict try/catch in [FirestoreService.fetchUserDisplayNames]; a failed,
///    unreadable (e.g. cached permission-denied) or missing profile degrades
///    to a `'Space Member'` placeholder instead of throwing.
///  * Any error that still escapes the underlying resolution stream (network
///    flaps, cancelled Firestore streams, …) is intercepted below and converted
///    into a fallback DATA emission, keeping the stream alive.
///  * A top-level catch around the whole generator body guarantees every exit
///    path yields a valid `Map<String, String>`, so watching widgets only ever
///    render [AsyncData] and never hit their `error:` branch again.
final spaceMembersProvider =
    StreamProvider.family<Map<String, String>, String>((ref, spaceId) async* {
  // Resolve the roster defensively and BEFORE any early return so this family
  // member always re-subscribes on upstream changes. userSpacesProvider may
  // legitimately be loading or erroring; `.value` degrades to an empty list.
  final spaces = ref.watch(userSpacesProvider).value ?? const <SpaceModel>[];
  SpaceModel? space;
  for (final candidate in spaces) {
    if (candidate.id == spaceId) {
      space = candidate;
      break;
    }
  }
  final members = <String>{
    for (final uid in space?.members ?? const <String>[])
      if (uid.isNotEmpty) uid,
  }.toList(growable: false);

  if (spaceId.isEmpty || members.isEmpty) {
    yield const <String, String>{};
    return;
  }

  try {
    yield* FirestoreService.instance.streamUserDisplayNames(members).transform(
          StreamTransformer.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Demote stream-level failures into a valid data emission so
              // the provider never transitions to AsyncError mid-listen.
              debugPrint('STREAM CRASH: $error');
              debugPrint(
                'spaceMembersProvider($spaceId): recovered stream error: '
                '$error\n$stackTrace',
              );
              sink.add(FirestoreService.fallbackMemberNames(members));
            },
          ),
        );
  } catch (e, st) {
    // Absolute last resort (unreachable in practice): still yield a valid
    // roster of degraded names rather than crashing the UI state.
    debugPrint('STREAM CRASH: $e');
    debugPrint(
      'spaceMembersProvider($spaceId): fatal failure, yielding fallback '
      'roster: $e\n$st',
    );
    yield FirestoreService.fallbackMemberNames(members);
  }
});
