import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../services/firestore_service.dart';

final firestorePlannerStreamProvider = StreamProvider<List<PlannerModel>>((ref) {
  final stream = FirestoreService.instance.streamPlannerEntries();
  stream.listen((tasks) {
    Future.microtask(() {
      FirestoreService.instance.runAutomaticDataCleanup(tasks);
    });
  });
  return stream;
});

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
    final asyncEntries = ref.watch(firestorePlannerStreamProvider);
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
    final asyncEntries = ref.watch(firestorePlannerStreamProvider);
    final entries = asyncEntries.value ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return entries.where((e) {
      final taskDay = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      if (taskDay == day) return true;
      if (day == today && taskDay.isBefore(today) && !e.isDone) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}