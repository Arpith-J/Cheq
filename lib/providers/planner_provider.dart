// lib/providers/planner_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';

class PlannerNotifier extends Notifier<List<PlannerModel>> {
  @override
  List<PlannerModel> build() => [];

  void addEntry(PlannerModel entry) => state = [...state, entry];

  void removeEntry(String id) =>
      state = state.where((e) => e.id != id).toList();

  void toggleDone(String id) {
    state = [
      for (final entry in state)
        if (entry.id == id)
          entry.copyWith(isDone: !entry.isDone)
        else
          entry,
    ];
  }

  void markNotified(String id) {
    state = [
      for (final entry in state)
        if (entry.id == id) entry.copyWith(isNotified: true) else entry,
    ];
  }

  void updateEntry(PlannerModel updated) {
    state = [
      for (final entry in state)
        if (entry.id == updated.id) updated else entry,
    ];
  }
}

final plannerProvider = NotifierProvider<PlannerNotifier, List<PlannerModel>>(
  PlannerNotifier.new,
);

/// Derived — entries for a specific date, sorted by start time.
final plannerForDateProvider =
    Provider.family<List<PlannerModel>, DateTime>((ref, date) {
  final entries = ref.watch(plannerProvider);
  return entries
      .where((e) =>
          e.startTime.year  == date.year &&
          e.startTime.month == date.month &&
          e.startTime.day   == date.day)
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
});