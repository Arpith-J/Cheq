import '../models/planner_model.dart';
import '../services/firestore_service.dart';

class LiquidRescheduler {
  
  /// Rebalances the day's tasks starting from a specific time.
  static Future<void> rebalance(List<PlannerModel> todaysTasks, DateTime startFrom) async {
    // 1. Get tasks that are NOT done and are scheduled AFTER the interruption
    final pendingTasks = todaysTasks.where((t) {
      return !t.isDone && t.endTime.isAfter(startFrom);
    }).toList();

    // 2. Separate into Fixed (Rocks) and Flexible (Water)
    final lockedTasks = pendingTasks.where((t) => t.isTimeLocked).toList();
    final flexibleTasks = pendingTasks.where((t) => !t.isTimeLocked).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime)); // Keep original priority order

    if (flexibleTasks.isEmpty) return; // Nothing to shift!

    DateTime timeCursor = startFrom;
    List<PlannerModel> updatedTasksToSave = [];

    // 3. Flow the flexible tasks into the gaps
    for (var flexTask in flexibleTasks) {
      final duration = flexTask.endTime.difference(flexTask.startTime);
      bool slotFound = false;

      while (!slotFound) {
        final proposedEnd = timeCursor.add(duration);

        // Check if this proposed block overlaps with any locked task
        final overlaps = lockedTasks.where((locked) {
          return timeCursor.isBefore(locked.endTime) && proposedEnd.isAfter(locked.startTime);
        }).toList();

        if (overlaps.isEmpty) {
          // Found an empty gap!
          updatedTasksToSave.add(flexTask.copyWith(
            startTime: timeCursor,
            endTime: proposedEnd,
          ));
          timeCursor = proposedEnd; // Move cursor to the end of this task
          slotFound = true;
        } else {
          // Hit a locked task. Jump the cursor to the end of that locked task.
          overlaps.sort((a, b) => b.endTime.compareTo(a.endTime));
          timeCursor = overlaps.first.endTime;
        }
      }
    }

    // 4. Push the reshuffled tasks to Firestore in one smooth batch
    if (updatedTasksToSave.isNotEmpty) {
      await FirestoreService.instance.saveTasksBatch(updatedTasksToSave);
    }
  }
}