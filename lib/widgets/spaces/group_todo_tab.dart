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

  /// Opens the to-do editing sheet pre-filled with [task]. Saving reuses the
  /// task's existing document id, so `saveGroupTask`'s `SetOptions(merge: true)`
  /// overwrites the Firestore document instead of creating a duplicate.
  Future<void> _openEditSheet(PlannerModel task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GroupTodoEditSheet(
        spaceId: widget.spaceId,
        initialEntry: task,
      ),
    );
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

    // Tapping anywhere outside the add-task field drops focus, dismissing the
    // keyboard and hiding the cursor.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Column(
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
                          onEdit: () => _openEditSheet(task),
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
      ),
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
    required this.onEdit,
    required this.onDelete,
  });

  final String spaceId;
  final PlannerModel task;
  final bool isBusy;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
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
        onTap: onEdit,
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
// Edit sheet — title-only editor for an existing shared checklist item
// ---------------------------------------------------------------------------

/// Bottom sheet mirroring this tab's minimal to-do creation UX (a single
/// title field). [initialEntry] pre-fills the editor and is re-saved with its
/// original document id on Save, so Firestore merge-overwrites in place.
class _GroupTodoEditSheet extends StatefulWidget {
  const _GroupTodoEditSheet({
    required this.spaceId,
    required this.initialEntry,
  });

  final String spaceId;
  final PlannerModel initialEntry;

  @override
  State<_GroupTodoEditSheet> createState() => _GroupTodoEditSheetState();
}

class _GroupTodoEditSheetState extends State<_GroupTodoEditSheet> {
  late final TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialEntry.title);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocus.requestFocus();
      // Select the existing text so typing replaces it outright.
      _titleCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleCtrl.text.length,
      );
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _titleCtrl.text.trim();
    if (_isSaving || text.isEmpty) {
      _titleFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);

    // Same id + `SetOptions(merge: true)` inside saveGroupTask overwrites the
    // existing document; completion state and creation order are untouched.
    await FirestoreService.instance.saveGroupTask(
      widget.spaceId,
      widget.initialEntry.copyWith(title: text),
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Edit Task',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                focusNode: _titleFocus,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
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
