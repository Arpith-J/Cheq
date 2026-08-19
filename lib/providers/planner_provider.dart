import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../services/firestore_service.dart';
import '../utils/stream_merge.dart';
import 'auth_provider.dart';
import 'spaces_provider.dart';
import 'task_settings_provider.dart';

/// Live planner stream, reacted to the auth state. On a fresh install the
/// FirebaseAuth session restores asynchronously; without this dependency a
/// provider built while `currentUser` was null caches an empty planner list
/// forever and the Planner UI never hydrates after login.
///
/// Personal-only: used by the widget sync path, week header badges, boot
/// pre-warming and reward/stats logic. The Planner UI itself consumes the
/// [mergedPlannerStreamProvider] below.
final firestorePlannerStreamProvider = StreamProvider<List<PlannerModel>>(
  (ref) {
    return ref.watch(authStateProvider).when(
          data: (user) => user == null
              ? Stream.value(const <PlannerModel>[])
              : FirestoreService.instance.streamPlannerEntries(user.uid),
          loading: () => Stream.value(const <PlannerModel>[]),
          error: (_, __) => Stream.value(const <PlannerModel>[]),
        );
  },
);

/// Merged planner stream shown on the main dashboard. Combines the user's
/// personal tasks (`users/{uid}/planner`) with the tasks assigned to them (or
/// to 'Everyone') in every active Space (`spaces/{spaceId}/tasks`), gated by
/// the [showGroupTasksProvider] toggle. When the toggle is off (or no Spaces
/// exist yet) it degrades to the personal-only stream.
///
/// ONLY time-blocked group tasks (a real `startTime < endTime` window that is
/// `isTimeLocked`) leak onto the planner timeline. Point-in-time checklist
/// items from the Group To-Do tab are excluded here — they surface on the
/// dashboard's To-Do list instead (see `mergedTodoCollectionsProvider`, which
/// applies the exact inverse of [isGroupTimeBlocked]).
final mergedPlannerStreamProvider = StreamProvider<List<PlannerModel>>(
  (ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return Stream.value(const <PlannerModel>[]);

    final uid = user.uid;
    final personal = FirestoreService.instance.streamPlannerEntries(uid);

    if (!ref.watch(showGroupTasksProvider)) return personal;

    return ref.watch(userSpacesProvider).when(
          data: (spaces) => mergeSpacesStreams<PlannerModel>(
            personal: personal,
            spaces: spaces,
            idOf: (task) => task.id,
            perSpace: (spaceId) => FirestoreService.instance
                .streamGroupTasks(spaceId)
                .map((tasks) => tasks
                    .where((t) =>
                        isGroupTaskRelevantTo(uid, t) &&
                        isGroupTimeBlocked(t))
                    .toList()),
          ),
          loading: () => personal,
          error: (_, _) => personal,
        );
  },
);

class PlannerNotifier extends Notifier<List<PlannerModel>> {
  @override
  List<PlannerModel> build() => [];

  void addEntry(PlannerModel entry) => state = [...state, entry];

  void removeEntry(String id) =>
      state = state.where((e) => e.id != id).toList();

  void toggleDone(String id) {
    state = [
      for (final entry in state)
        if (entry.id == id) entry.copyWith(isDone: !entry.isDone) else entry,
    ];
  }

  void updateEntry(PlannerModel updated) {
    state = [
      for (final entry in state)
        if (entry.id == updated.id) updated else entry,
    ];
  }
}

final plannerProvider =
    NotifierProvider<PlannerNotifier, List<PlannerModel>>(
  PlannerNotifier.new,
);

final plannerForDateProvider =
    NotifierProvider.family<PlannerForDateNotifier, List<PlannerModel>, DateTime>(
  PlannerForDateNotifier.new,
);

class PlannerForDateNotifier extends Notifier<List<PlannerModel>> {
  PlannerForDateNotifier(this.targetDateRaw);

  final DateTime targetDateRaw;

  @override
  List<PlannerModel> build() {
    final targetDate =
        DateTime(targetDateRaw.year, targetDateRaw.month, targetDateRaw.day);
    final asyncEntries = ref.watch(mergedPlannerStreamProvider);
    final allEntries = asyncEntries.value ?? [];

    return allEntries.where((entry) {
      final taskDate =
          DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);

      if (taskDate.isAtSameMomentAs(targetDate)) return true;
      if (taskDate.isAfter(targetDate)) return false;

      switch (entry.repeatInterval) {
        case RepeatInterval.none:
          return false;
        case RepeatInterval.daily:
          return true;
        case RepeatInterval.weekly:
          return entry.startTime.weekday == targetDate.weekday;
        case RepeatInterval.monthly:
          return entry.startTime.day == targetDate.day;
        case RepeatInterval.custom:
          if (entry.customInterval == null) return false;
          final difference = targetDate.difference(taskDate).inDays;
          final stepInDays = entry.customInterval!.inDays;
          return stepInDays > 0 && (difference % stepInDays == 0);
      }
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}
final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  SelectedDayNotifier.new,
);

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void changeDay(DateTime newDay) {
    state = DateTime(newDay.year, newDay.month, newDay.day);
  }
}

final selectedDayEntriesProvider =
    NotifierProvider<SelectedDayEntriesNotifier, List<PlannerModel>>(
  SelectedDayEntriesNotifier.new,
);

class SelectedDayEntriesNotifier extends Notifier<List<PlannerModel>> {
  @override
  List<PlannerModel> build() {
    final day = ref.watch(selectedDayProvider);
    final asyncEntries = ref.watch(mergedPlannerStreamProvider);
    final entries = asyncEntries.value ?? [];
    final carryOverEnabled = ref.watch(carryOverTasksProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return entries.where((e) {
      final taskDay = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      if (taskDay == day) return true;
      if (day == today && taskDay.isBefore(today) && !e.isDone) {
        return true;
      }
      if (day == today && taskDay.isBefore(today) && !e.isDone) {
        return carryOverEnabled; 
      }
      return false;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}