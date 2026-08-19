// lib/providers/spaces_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/space_model.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Spaces — collaborative group state (Riverpod 3.0)
// ---------------------------------------------------------------------------

/// Live stream of the signed-in user's Spaces. Reacts to auth state so a
/// provider first built while `currentUser` was null does not cache an empty
/// list forever (mirrors `firestorePlannerStreamProvider`).
final userSpacesProvider = StreamProvider<List<SpaceModel>>((ref) {
  return ref.watch(authStateProvider).when(
        data: (user) => user == null
            ? Stream.value(const <SpaceModel>[])
            : FirestoreService.instance.streamUserSpaces(),
        loading: () => Stream.value(const <SpaceModel>[]),
        error: (_, _) => Stream.value(const <SpaceModel>[]),
      );
});

/// Async mutation controller for create/join/leave operations. Exposes proper
/// loading/error states (AsyncLoading / AsyncError) that the UI can watch while
/// Firestore's live [userSpacesProvider] stream repopulates on its own.
final spacesNotifierProvider =
    AsyncNotifierProvider<SpacesNotifier, void>(SpacesNotifier.new);

class SpacesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a Space and returns it (so the UI can show the room code), or
  /// null on failure. The live stream picks up the new document automatically.
  Future<SpaceModel?> createSpace(String name) async {
    state = const AsyncLoading<void>();
    try {
      final space = await FirestoreService.instance.createSpace(name);
      state = const AsyncData<void>(null);
      return space;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return null;
    }
  }

  /// Joins a Space by 6-digit room code. Returns true when a matching Space was
  /// found and the membership was applied.
  Future<bool> joinSpace(String code) async {
    state = const AsyncLoading<void>();
    try {
      final joined = await FirestoreService.instance.joinSpaceByCode(code);
      state = const AsyncData<void>(null);
      return joined;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }

  /// Leaves a Space. Returns true on success; the live stream removes the
  /// Space from the UI automatically once Firestore confirms (or optimistically
  /// from the local offline cache).
  Future<bool> leaveSpace(String spaceId) async {
    state = const AsyncLoading<void>();
    try {
      await FirestoreService.instance.leaveSpace(spaceId);
      state = const AsyncData<void>(null);
      return true;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }
}
