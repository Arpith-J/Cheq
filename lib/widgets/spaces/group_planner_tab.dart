// lib/widgets/spaces/group_planner_tab.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/group_tasks_provider.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';
import 'group_task_sheet.dart';

/// The 'Group Planner' tab for a Space: a shared, chronological timeline of
/// time-blocked tasks from the `tasks` subcollection. Visually mirrors the
/// personal Daily Planner (time rail + divider + task card) while only showing
/// entries with a real time window, grouped by the day they start on. Every
/// member watches the same live stream, and the [FloatingActionButton]
/// schedules new shared time blocks via [GroupTaskSheet].
class GroupPlannerTab extends ConsumerStatefulWidget {
  const GroupPlannerTab({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<GroupPlannerTab> createState() => _GroupPlannerTabState();
}

class _GroupPlannerTabState extends ConsumerState<GroupPlannerTab> {
  /// Id of the task whose checkbox toggle is currently in flight, so a rapid
  /// double-tap can never double-award the shared coin reward.
  String? _busyTaskId;

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
        content: Text('Remove "${task.title}" from the group schedule?'),
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

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: GroupTaskSheet(spaceId: widget.spaceId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(groupTasksProvider(widget.spaceId));
    final memberNames =
        ref.watch(spaceMembersProvider(widget.spaceId)).value ??
            const <String, String>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load the group schedule.\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (tasks) {
          // Only time-blocked tasks make it onto the timeline; the Group To-Do
          // checklist reuses the same subcollection and should stay invisible
          // here. Sorted chronologically so the timeline reads top-to-bottom.
          final scheduled = tasks
              .where((task) => task.endTime.isAfter(task.startTime))
              .toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          if (scheduled.isEmpty) return const _GroupPlannerEmpty();

          // Group into per-day sections to mirror the personal Daily Planner.
          final byDay = <DateTime, List<PlannerModel>>{};
          for (final task in scheduled) {
            final day = DateTime(
              task.startTime.year,
              task.startTime.month,
              task.startTime.day,
            );
            byDay.putIfAbsent(day, () => []).add(task);
          }
          final days = byDay.keys.toList()..sort();

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: days.length,
            itemBuilder: (ctx, i) {
              final day = days[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayHeader(day: day),
                  for (final task in byDay[day]!)
                    _GroupPlannerTaskTile(
                      task: task,
                      memberNames: memberNames,
                      isBusy: _busyTaskId == task.id,
                      onToggle: () => _toggleTask(task),
                      onDelete: () => _confirmDelete(task),
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'group_planner_fab',
        tooltip: 'Schedule a task',
        onPressed: _openAddSheet,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day header — splits the timeline into Today / Tomorrow / dated sections
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));

    if (day.isAtSameMomentAs(today)) return 'Today';
    if (day.isAtSameMomentAs(tomorrow)) return 'Tomorrow';
    if (day.isAtSameMomentAs(yesterday)) return 'Yesterday';
    return '${_weekdays[day.weekday - 1]}, '
        '${_months[day.month - 1]} ${day.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            _label(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline task tile — mirrors the personal planner's TaskRow card
// ---------------------------------------------------------------------------

class _GroupPlannerTaskTile extends StatelessWidget {
  const _GroupPlannerTaskTile({
    required this.task,
    required this.memberNames,
    required this.isBusy,
    required this.onToggle,
    required this.onDelete,
  });

  final PlannerModel task;
  final Map<String, String> memberNames;
  final bool isBusy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String? _assigneeLabel() {
    if (task.assignedTo == null) return null;
    if (task.assignedTo == FirebaseAuth.instance.currentUser?.uid) {
      return 'You';
    }
    return memberNames[task.assignedTo] ?? 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isOverdue = !task.isDone && now.isAfter(task.endTime);
    final assignee = _assigneeLabel();
    final hasCategory = task.categoryName != null && task.categoryColor != null;
    final categoryColor = hasCategory ? Color(task.categoryColor!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: (hasCategory && !task.isDone)
            ? categoryColor!.withValues(alpha: 0.15)
            : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue
              ? cs.error.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.5),
          width: isOverdue ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: (hasCategory && !task.isDone)
                    ? categoryColor!
                    : Colors.transparent,
                width: (hasCategory && !task.isDone) ? 4.0 : 0.0,
              ),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onLongPress: onDelete,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Time rail — mirrors TaskRow's fixed-width time column.
                  Container(
                    width: 82,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _formatTime(task.startTime),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: task.isDone
                            ? cs.onSurface.withValues(alpha: 0.3)
                            : isOverdue
                                ? cs.error
                                : cs.primary,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    color: task.isDone
                        ? cs.outlineVariant.withValues(alpha: 0.3)
                        : cs.primary.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isOverdue || assignee != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (isOverdue)
                                          _chip(
                                            bg: cs.errorContainer,
                                            fg: cs.onErrorContainer,
                                            borderColor: Colors.transparent,
                                            label: 'OVERDUE',
                                          ),
                                        if (assignee != null)
                                          _chip(
                                            bg: cs.secondaryContainer
                                                .withValues(alpha: 0.6),
                                            fg: cs.onSecondaryContainer,
                                            borderColor: cs.secondary
                                                .withValues(alpha: 0.25),
                                            icon: Icons.person_rounded,
                                            label: assignee,
                                          ),
                                      ],
                                    ),
                                  ),
                                Text(
                                  task.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: task.isDone
                                        ? cs.onSurface.withValues(alpha: 0.35)
                                        : isOverdue
                                            ? cs.error
                                            : cs.onSurface,
                                    decoration: task.isDone
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    decorationColor:
                                        cs.onSurface.withValues(alpha: 0.4),
                                    decorationThickness: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: task.isDone,
                              onChanged:
                                  isBusy ? null : (_) => onToggle(),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required Color bg,
    required Color fg,
    required Color borderColor,
    IconData? icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _GroupPlannerEmpty extends StatelessWidget {
  const _GroupPlannerEmpty();

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
                Icons.calendar_today_rounded,
                size: 34,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Nothing scheduled yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the + button to block out time on the group schedule.',
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
