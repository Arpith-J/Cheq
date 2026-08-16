// lib/providers/group_sync_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/group_sync_service.dart';

/// Exposes the singleton sync service to the widget tree.
final groupSyncServiceProvider = Provider<GroupSyncService>(
  (ref) => GroupSyncService.instance,
);

/// Immutable snapshot of the hybrid group-sync status.
class GroupSyncStatus {
  const GroupSyncStatus({this.lastSyncAt, this.isSyncing = false});

  /// Last moment group data was successfully pulled from Firestore (null when
  /// the worker has never completed on this device).
  final DateTime? lastSyncAt;

  /// True while a foreground sync is in flight.
  final bool isSyncing;

  GroupSyncStatus copyWith({DateTime? lastSyncAt, bool? isSyncing}) {
    return GroupSyncStatus(
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

/// Live sync status. The notifier exposes [syncNow] which is invoked from the
/// app-lifecycle resume handler so group data refreshes the moment the user
/// returns to the app.
final groupSyncProvider =
    AsyncNotifierProvider<GroupSyncNotifier, GroupSyncStatus>(
  GroupSyncNotifier.new,
);

class GroupSyncNotifier extends AsyncNotifier<GroupSyncStatus> {
  @override
  Future<GroupSyncStatus> build() async {
    final lastSyncAt = await GroupSyncService.instance.readLastSyncAt();
    return GroupSyncStatus(lastSyncAt: lastSyncAt);
  }

  /// Foreground sync trigger (also invoked on app resume). Runs the Firestore
  /// group fetch and records the fresh timestamp. Fire-and-forget and safe
  /// offline — the service swallows every failure.
  Future<void> syncNow() async {
    final previous = state.value ?? const GroupSyncStatus();

    // Reflect the in-flight state so the UI can show a spinner if needed.
    state = AsyncValue.data(previous.copyWith(isSyncing: true));

    state = await AsyncValue.guard(() async {
      final syncAt = await GroupSyncService.instance.syncGroupTasks();
      return previous.copyWith(
        lastSyncAt: syncAt ?? previous.lastSyncAt,
        isSyncing: false,
      );
    });
  }
}
