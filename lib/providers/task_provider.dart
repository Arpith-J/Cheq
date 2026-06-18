// lib/providers/task_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_model.dart';

class TasksNotifier extends Notifier<List<TaskModel>> {
  @override
  List<TaskModel> build() => [];

  void addTask(TaskModel task) => state = [...state, task];

  void removeTask(String id) =>
      state = state.where((t) => t.id != id).toList();

  void toggleCompletion(String id) {
    state = [
      for (final task in state)
        if (task.id == id)
          task.copyWith(isCompleted: !task.isCompleted)
        else
          task,
    ];
  }

  void updateTask(TaskModel updated) {
    state = [
      for (final task in state) if (task.id == updated.id) updated else task,
    ];
  }
}

final tasksProvider = NotifierProvider<TasksNotifier, List<TaskModel>>(
  TasksNotifier.new,
);

/// Derived — incomplete tasks sorted by due date ascending.
final pendingTasksProvider = Provider<List<TaskModel>>((ref) {
  final tasks = ref.watch(tasksProvider);
  return tasks.where((t) => !t.isCompleted).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
});