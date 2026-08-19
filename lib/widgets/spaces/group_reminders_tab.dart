// lib/widgets/spaces/group_reminders_tab.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/group_reminders_provider.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';
import 'group_reminder_sheet.dart';

/// The 'Group Reminders' tab for a Space: a shared list of timed alerts from
/// the `reminders` subcollection. Each row shows the title, the exact alert
/// trigger time, and who it is delegated to. A checkbox acknowledges a reminder
/// (no coins, unlike group-task completion), and the [FloatingActionButton]
/// creates new reminders via [GroupReminderSheet].
class GroupRemindersTab extends ConsumerStatefulWidget {
  const GroupRemindersTab({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<GroupRemindersTab> createState() => _GroupRemindersTabState();
}

class _GroupRemindersTabState extends ConsumerState<GroupRemindersTab> {
  /// Id of the reminder whose acknowledge toggle is currently in flight.
  String? _busyReminderId;

  Future<void> _toggleAcknowledged(PlannerModel reminder) async {
    if (_busyReminderId != null) return;

    setState(() => _busyReminderId = reminder.id);
    await FirestoreService.instance.toggleGroupReminderAcknowledged(
      spaceId: widget.spaceId,
      reminderId: reminder.id,
      acknowledged: !reminder.isDone,
    );
    if (!mounted) return;
    setState(() => _busyReminderId = null);
  }

  Future<void> _confirmDelete(PlannerModel reminder) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Remove "${reminder.title}" from the group reminders?'),
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
    await FirestoreService.instance
        .deleteGroupReminder(widget.spaceId, reminder.id);
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: GroupReminderSheet(spaceId: widget.spaceId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(groupRemindersProvider(widget.spaceId));
    final memberNames =
        ref.watch(spaceMembersProvider(widget.spaceId)).value ??
            const <String, String>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: remindersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load group reminders.\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (reminders) {
          // Soonest trigger first, so what's due next is always on top.
          final sorted = [...reminders]
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          if (sorted.isEmpty) return const _GroupRemindersEmpty();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final reminder = sorted[i];
              return _ReminderTile(
                reminder: reminder,
                memberNames: memberNames,
                isBusy: _busyReminderId == reminder.id,
                onToggle: () => _toggleAcknowledged(reminder),
                onDelete: () => _confirmDelete(reminder),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'group_reminders_fab',
        tooltip: 'Create a reminder',
        onPressed: _openCreateSheet,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reminder row — title, exact target time, assignee + acknowledge checkbox
// ---------------------------------------------------------------------------

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.memberNames,
    required this.isBusy,
    required this.onToggle,
    required this.onDelete,
  });

  final PlannerModel reminder;
  final Map<String, String> memberNames;
  final bool isBusy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _targetLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final todayOffset = target.difference(today).inDays;
    final prefix = switch (todayOffset) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => '${_weekdays[dt.weekday - 1]}, '
          '${_months[dt.month - 1]} ${dt.day}',
    };
    return '$prefix • ${_formatTime(dt)}';
  }

  String _assigneeLabel() {
    if (reminder.assignedTo == null) return 'Everyone';
    if (reminder.assignedTo == FirebaseAuth.instance.currentUser?.uid) {
      return 'You';
    }
    return memberNames[reminder.assignedTo] ?? 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isMissed = !reminder.isDone && now.isAfter(reminder.startTime);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMissed
              ? cs.error.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.5),
          width: isMissed ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        onLongPress: onDelete,
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isMissed
                ? cs.errorContainer.withValues(alpha: 0.6)
                : cs.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isMissed
                ? Icons.alarm_off_rounded
                : Icons.notifications_active_rounded,
            size: 18,
            color: isMissed ? cs.onErrorContainer : cs.onPrimaryContainer,
          ),
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: reminder.isDone
                ? cs.onSurface.withValues(alpha: 0.38)
                : cs.onSurface,
            decoration: reminder.isDone
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            decorationColor: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 13,
                color: reminder.isDone
                    ? cs.onSurface.withValues(alpha: 0.3)
                    : isMissed
                        ? cs.error
                        : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _targetLabel(reminder.startTime),
                style: TextStyle(
                  fontSize: 12,
                  color: reminder.isDone
                      ? cs.onSurface.withValues(alpha: 0.3)
                      : isMissed
                          ? cs.error
                          : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AssigneeChip(
              label: _assigneeLabel(),
              isEveryone: reminder.assignedTo == null,
              isDone: reminder.isDone,
            ),
            const SizedBox(width: 4),
            Checkbox(
              value: reminder.isDone,
              onChanged: isBusy ? null : (_) => onToggle(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assignee chip — 'Everyone' vs. a member's resolved display name
// ---------------------------------------------------------------------------

class _AssigneeChip extends StatelessWidget {
  const _AssigneeChip({
    required this.label,
    required this.isEveryone,
    required this.isDone,
  });

  final String label;
  final bool isEveryone;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isEveryone
            ? cs.surfaceContainerHigh
            : cs.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEveryone
              ? cs.outlineVariant.withValues(alpha: 0.4)
              : cs.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEveryone ? Icons.groups_rounded : Icons.person_rounded,
            size: 11,
            color: isEveryone
                ? cs.onSurfaceVariant
                : cs.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isEveryone
                  ? cs.onSurfaceVariant
                  : cs.onSecondaryContainer,
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

class _GroupRemindersEmpty extends StatelessWidget {
  const _GroupRemindersEmpty();

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
                Icons.notifications_none_rounded,
                size: 34,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No reminders yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the + button to remind the group — or someone in it — '
              'about something important.',
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
