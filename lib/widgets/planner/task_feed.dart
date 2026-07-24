import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/planner_provider.dart';
import '../../providers/task_settings_provider.dart'; // <-- Added this import
import 'task_row.dart';

class TaskFeed extends ConsumerWidget {
  const TaskFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamState = ref.watch(firestorePlannerStreamProvider);
    if (streamState.isLoading && !streamState.hasValue) {
      return const SizedBox.shrink(); 
    }
    
    // 1. Get the raw list of entries
    final rawEntries = ref.watch(selectedDayEntriesProvider);
    
    // 2. Get the currently selected date in the planner
    final selectedDate = ref.watch(selectedDayProvider);
    
    // 3. Read the toggle state from your settings
    final isCarryOverEnabled = ref.watch(carryOverTasksProvider); 

    // 4. Filter the list dynamically
    final entries = rawEntries.where((task) {
      // Strip out the time to cleanly compare just the days
      final taskDate = DateTime(task.endTime.year, task.endTime.month, task.endTime.day);
      final currentDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

      final isToday = taskDate.isAtSameMomentAs(currentDate);
      final isPastAndPending = taskDate.isBefore(currentDate) && !task.isDone;

      // Always show tasks explicitly scheduled for the selected day
      if (isToday) {
        return true; 
      }
      
      // If it is a past unfinished task, only show it if the toggle is ON
      if (isCarryOverEnabled && isPastAndPending) {
        return true; 
      }

      // Hide everything else
      return false; 
    }).toList();

    if (entries.isEmpty) return const EmptyDay();
    
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: entries.length,
      itemBuilder: (_, i) => TaskRow(entry: entries[i]),
    );
  }
}

class EmptyDay extends StatelessWidget {
  const EmptyDay({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_rounded,
              size: 64, color: cs.onSurface.withValues(alpha: 0.12)),
          const SizedBox(height: 16),
          Text(
            'Nothing scheduled',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the button below to add a task.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
          ),
        ],
      ),
    );
  }
}