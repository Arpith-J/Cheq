import 'dart:async';

import '../models/planner_model.dart';
import '../models/space_model.dart';

/// Whether a shared task should surface on the current user's personal
/// dashboard: explicitly assigned to them, assigned to 'Everyone', or left
/// unassigned. Other members' tasks stay on the Space timeline only.
bool isGroupTaskRelevantTo(String uid, PlannerModel task) =>
    task.assignedTo == null ||
    task.assignedTo == uid ||
    task.assignedTo == 'Everyone';

/// Whether a shared task is a genuine time-blocked entry for the Planner
/// timeline (Group Planner tab + personal dashboard planner). Group Planner
/// tasks are created with a real `start < end` window AND `isTimeLocked: true`;
/// Group To-Do checklist items are point-in-time (`start == end`) and never
/// time-locked. Requiring BOTH guards keeps even legacy checklist items that
/// still carry a stale +30-minute window off the planner timeline, so they
/// surface on the dashboard To-Do list instead.
///
/// Consumers must use this predicate and its exact inverse to partition the
/// shared `tasks` subcollection — every relevant group task lands in exactly
/// one of the two dashboard streams, never both and never dropped.
bool isGroupTimeBlocked(PlannerModel task) =>
    task.isTimeLocked && task.startTime.isBefore(task.endTime);

/// Merges a personal [Stream] of [T] with one live per-Space [Stream] of [T]
/// into a single list stream.
///
/// Whenever any source emits, the combined list is re-emitted. Items are
/// de-duplicated by [idOf] so the same document can never appear twice, and
/// every group subscription is torn down when the controller is cancelled.
Stream<List<T>> mergeSpacesStreams<T>({
  required Stream<List<T>> personal,
  required List<SpaceModel> spaces,
  required String Function(T item) idOf,
  required Stream<List<T>> Function(String spaceId) perSpace,
}) {
  late StreamController<List<T>> controller;

  List<T> personalLatest = const [];
  final groupBySpace = <String, List<T>>{};
  final groupSubs = <String, StreamSubscription<List<T>>>{};
  StreamSubscription<List<T>>? personalSub;

  void emit() {
    if (controller.isClosed) return;
    final seen = <String>{};
    final merged = <T>[
      for (final item in personalLatest)
        if (seen.add(idOf(item))) item,
      for (final list in groupBySpace.values)
        for (final item in list)
          if (seen.add(idOf(item))) item,
    ];
    controller.add(merged);
  }

  controller = StreamController<List<T>>(
    onListen: () {
      personalSub = personal.listen((items) {
        personalLatest = items;
        emit();
      });

      for (final space in spaces) {
        if (space.id.isEmpty) continue;
        groupSubs[space.id] = perSpace(space.id).listen((items) {
          groupBySpace[space.id] = items;
          emit();
        });
        groupBySpace[space.id] = const [];
      }

      emit();
    },
    onCancel: () {
      personalSub?.cancel();
      for (final sub in groupSubs.values) {
        sub.cancel();
      }
      groupSubs.clear();
      groupBySpace.clear();
    },
  );

  return controller.stream;
}
