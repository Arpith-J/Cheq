import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';

// ── CORE STATE MANAGEMENT NOTIFIER ───────────────────────────────────────────
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

final plannerProvider = NotifierProvider<PlannerNotifier, List<PlannerModel>>(
  PlannerNotifier.new,
);

// ── RECURRENT INTERVAL EVALUATION PIPELINE (Riverpod 3.0 Family) ─────────────
// Replaces legacy functional Provider.family with a modern read-only family Notifier
final plannerForDateProvider = NotifierProvider.family<PlannerForDateNotifier, List<PlannerModel>, DateTime>(
  PlannerForDateNotifier.new,
);

class PlannerForDateNotifier extends Notifier<List<PlannerModel>> {
  PlannerForDateNotifier(this.targetDateRaw);
  final DateTime targetDateRaw;
  @override
  List<PlannerModel> build() {
    final targetDate = DateTime(targetDateRaw.year, targetDateRaw.month, targetDateRaw.day);
    final allEntries = ref.watch(plannerProvider);

    return allEntries.where((entry) {
      final taskDate = DateTime(entry.startTime.year, entry.startTime.month, entry.startTime.day);

      // 1. If it's the exact day the task was created, always show it
      if (taskDate.isAtSameMomentAs(targetDate)) return true;

      // 2. Do not show tasks scheduled to occur in the future relative to the selected day
      if (taskDate.isAfter(targetDate)) return false;

      // 3. Evaluate matching metrics based on the repeat intervals
      switch (entry.repeatInterval) {
        case RepeatInterval.none:
          return false;

        case RepeatInterval.daily:
          return true; // Appears every day after creation

        case RepeatInterval.weekly:
          // Appears if it falls on the exact same day of the week (e.g., every Monday)
          return entry.startTime.weekday == targetDate.weekday;

        case RepeatInterval.monthly:
          // Appears if it falls on the exact same day of the month (e.g., every 15th)
          return entry.startTime.day == targetDate.day;

        case RepeatInterval.custom:
          if (entry.customInterval == null) return false;
          // Calculate if the duration delta between days is perfectly divisible by the custom interval step
          final difference = targetDate.difference(taskDate).inDays;
          final stepInDays = entry.customInterval!.inDays;
          return stepInDays > 0 && (difference % stepInDays == 0);
      }
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}