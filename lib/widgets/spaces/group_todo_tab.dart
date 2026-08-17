// lib/widgets/spaces/group_todo_tab.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/group_tasks_provider.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/stream_merge.dart';

/// The 'Group To-Do' tab for a Space: a shared checklist stored in the `tasks`
/// subcollection of the Space document. Every member watches the same live
/// stream, and checking a task off personally awards the standard coin reward
/// (reward/penalty applied atomically in `toggleGroupTaskCompletion`).
///
/// The `tasks` subcollection also holds time-blocked Group Planner entries, so
/// this tab applies the exact inverse of `isGroupTimeBlocked` (the same
/// partition used by the personal dashboard's To-Do stream) to show ONLY
/// point-in-time checklist items. Genuine time windows created in the Group
/// Planner stay on the Group Planner timeline and never bleed in here.
class GroupTodoTab extends ConsumerStatefulWidget {
  const GroupTodoTab({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<GroupTodoTab> createState() => _GroupTodoTabState();
}

class _GroupTodoTabState extends ConsumerState<GroupTodoTab> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  /// Id of the task whose toggle is currently in flight. Its checkbox is
  /// disabled meanwhile so a rapid double-tap can never double-award coins.
  String? _busyTaskId;

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _addTask() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final task = PlannerModel(
      id: 'group_${now.millisecondsSinceEpoch}',
      title: text,
      // A checklist item is point-in-time (start == end), NOT a time window.
      // This is the discriminator that keeps Group To-Do items off the Group
      // Planner timeline and the personal Daily Planner, while letting them
      // surface on the dashboard To-Do list.
      startTime: now,
      endTime: now,
      // The owning Space is injected into the task so it always lives under
      // the correct `spaces/{spaceId}/tasks` subcollection.
      groupId: widget.spaceId,
      assignedTo: uid,
      createdAt: now,
    );

    await FirestoreService.instance.saveGroupTask(widget.spaceId, task);

    _addController.clear();
    _addFocus.requestFocus();
  }

  Future<void> _toggleTask(PlannerModel task) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _busyTaskId != null) return;

    setState(() => _busyTaskId = task.id);
    await FirestoreService.instance.toggleGroupTaskCompletion(
      spaceId: widget.spaceId,
      task: task,
      uid: uid,
    );
    if (!mounted) return;
    setState(() => _busyTaskId = null);
  }

  Future<void> _confirmDelete(PlannerModel task) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Remove "${task.title}" from the group checklist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await FirestoreService.instance.deleteGroupTask(widget.spaceId, task.id);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(groupTasksProvider(widget.spaceId));

    return Column(
      children: [
        Expanded(
          child: tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load group tasks.\n$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
            data: (tasks) {
              // Mirror the dashboard's To-Do segregation exactly: keep only
              // non-time-blocked checklist items. `isGroupTimeBlocked` requires
              // `isTimeLocked` AND a real `start < end` window, so it is the
              // same predicate — and its inverse — that the personal dashboard
              // uses to keep Group Planner entries off its To-Do list.
              final todos = tasks
                  .where((task) => !isGroupTimeBlocked(task))
                  .toList();

              return todos.isEmpty
                  ? const _GroupTodoEmpty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: todos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final task = todos[i];
                        return _GroupTaskTile(
                          spaceId: widget.spaceId,
                          task: task,
                          isBusy: _busyTaskId == task.id,
                          onToggle: () => _toggleTask(task),
                          onDelete: () => _confirmDelete(task),
                        );
                      },
                    );
            },
          ),
        ),
        _AddTaskBar(
          controller: _addController,
          focusNode: _addFocus,
          onSubmit: _addTask,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared task row
// ---------------------------------------------------------------------------

class _GroupTaskTile extends ConsumerWidget {
  const _GroupTaskTile({
    required this.spaceId,
    required this.task,
    required this.isBusy,
    required this.onToggle,
    required this.onDelete,
  });

  final String spaceId;
  final PlannerModel task;
  final bool isBusy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final iCompleted =
        task.completedBy.contains(FirebaseAuth.instance.currentUser?.uid);
    final memberNames = ref.watch(spaceMembersProvider(spaceId)).value ??
        const <String, String>{};

    // Resolve completedBy UIDs into display names for the subtitle.
    String? completedByText;
    if (task.completedBy.isNotEmpty) {
      final names = task.completedBy
          .map((uid) => memberNames[uid] ?? uid.substring(0, uid.length.clamp(0, 6)))
          .toList();
      completedByText = 'Finished by: ${names.join(', ')}';
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        onLongPress: onDelete,
        leading: Checkbox(
          value: iCompleted,
          onChanged: isBusy ? null : (_) => onToggle(),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: task.isDone
                ? cs.onSurface.withValues(alpha: 0.38)
                : cs.onSurface,
            decoration:
                task.isDone ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
        subtitle: completedByText != null
            ? Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 12, color: Colors.green),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      completedByText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom add-task bar
// ---------------------------------------------------------------------------

class _AddTaskBar extends StatelessWidget {
  const _AddTaskBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    hintText: 'Add a group task…',
                    filled: true,
                    fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSubmit,
                icon: const Icon(Icons.send_rounded, size: 20),
                tooltip: 'Add task',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _GroupTodoEmpty extends StatelessWidget {
  const _GroupTodoEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 34,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No shared tasks yet',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a task below — every member will see it instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
