import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/planner_provider.dart';
import '../../providers/notification_settings_provider.dart';
import '../../providers/rewards_provider.dart';
import '../../services/firestore_service.dart';
import 'add_task_sheet.dart';

class TaskRow extends ConsumerStatefulWidget {
  const TaskRow({super.key, required this.entry});
  final PlannerModel entry;

  @override
  ConsumerState<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<TaskRow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation _strikeAnim;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.entry.isDone ? 1.0 : 0.0,
    );
    _strikeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(TaskRow old) {
    super.didUpdateWidget(old);
    if (widget.entry.isDone != old.entry.isDone) {
      widget.entry.isDone ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTimeString(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<int> _showDeleteConfirmDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final isRecurring = widget.entry.repeatGroupId != null;

    return await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Text(isRecurring 
              ? 'This is a repeating task. Do you want to delete just this one, or all future tasks in this series?'
              : 'Are you sure you want to permanently delete this task?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 0), 
                child: const Text('Cancel'),
              ),
              if (isRecurring)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  onPressed: () => Navigator.pop(ctx, 1), 
                  child: const Text('This Only'),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                ),
                onPressed: () => Navigator.pop(ctx, 2), 
                child: Text(isRecurring ? 'All Future' : 'Delete'),
              ),
            ],
          ),
        ) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entry = widget.entry;
    final now = DateTime.now();

    final endDateTime = entry.endTime.isAfter(entry.startTime)
        ? entry.endTime
        : entry.endTime.add(const Duration(days: 1));

    final isOverdue = !entry.isDone && now.isAfter(endDateTime);
    
    // --- CATEGORY DATA EXTRACTION ---
    final hasCategory = entry.categoryName != null && entry.categoryColor != null;
    final categoryColor = hasCategory ? Color(entry.categoryColor!) : null;

    // Determine base border colors
    final baseBorderColor = isOverdue ? cs.error.withValues(alpha: 0.6) : cs.outlineVariant.withValues(alpha: 0.5);
    final baseBorderWidth = isOverdue ? 1.5 : 1.0;

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        try {
          await FirestoreService.instance.deleteTask(entry.id);
          syncNativeAlarms(ref);
          return true; 
        } catch (e) {
          debugPrint("Error dismissing: $e");
          return false;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          //color: cs.surface,
          color: (hasCategory && !entry.isDone) 
              ? categoryColor!.withValues(alpha: 0.15) // 15% tint of their category color!
              : cs.surface,
          borderRadius: BorderRadius.circular(14),
          // 1. Give the main card a standard, uniform border to prevent the crash
          border: Border.all(
            color: baseBorderColor, 
            width: baseBorderWidth,
          ),
        ),
        // 2. Wrap the inside with ClipRRect so our thick stripe curves perfectly
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13), 
          child: Container(
            decoration: BoxDecoration(
              // 3. Apply the colored stripe here on the inside
              border: Border(
                left: BorderSide(
                  color: (hasCategory && !entry.isDone) ? categoryColor! : Colors.transparent,
                  width: (hasCategory && !entry.isDone) ? 4.0 : 0.0,
                ),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              onLongPress: () async {
                final action = await _showDeleteConfirmDialog(context);
                if (action > 0 && mounted) {
                  if (action == 2 && entry.repeatGroupId != null) {
                    await FirestoreService.instance.deleteRecurringTaskGroup(entry.repeatGroupId!, entry.startTime);
                  } else {
                    await FirestoreService.instance.deleteTask(entry.id);
                  }
                  syncNativeAlarms(ref);
                }
              },
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 82,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                            alignment: Alignment.center,
                            child: Text(
                              _formatTimeString(entry.startTime),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: entry.isDone ? cs.onSurface.withValues(alpha: 0.3) : cs.primary,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            color: entry.isDone ? cs.outlineVariant.withValues(alpha: 0.3) : cs.primary.withValues(alpha: 0.35),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: AnimatedBuilder(
                                      animation: _strikeAnim,
                                      builder: (_, _) => Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          
                                          // --- FIXED: Row instead of Wrap for IntrinsicHeight safety ---
                                          if (isOverdue || hasCategory)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 6),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isOverdue)
                                                    Container(
                                                      margin: const EdgeInsets.only(right: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: cs.errorContainer,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'OVERDUE',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                          color: cs.onErrorContainer,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ),
                                                    
                                                  if (hasCategory)
                                                    Flexible(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: categoryColor!.withValues(alpha: entry.isDone ? 0.05 : 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(
                                                            color: categoryColor.withValues(alpha: entry.isDone ? 0.1 : 0.3),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            CircleAvatar(
                                                              backgroundColor: categoryColor.withValues(alpha: entry.isDone ? 0.3 : 1.0),
                                                              radius: 3.5,
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Flexible(
                                                              child: Text(
                                                                entry.categoryName!.toUpperCase(),
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: categoryColor.withValues(alpha: entry.isDone ? 0.4 : 0.85),
                                                                  letterSpacing: 0.5,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          // ------------------------------------------------
                                          
                                          Text(
                                            entry.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: entry.isDone ? cs.onSurface.withValues(alpha: 0.35) : isOverdue ? cs.error : cs.onSurface,
                                              decoration: entry.isDone ? TextDecoration.lineThrough : TextDecoration.none,
                                              decorationColor: cs.onSurface.withValues(alpha: 0.4),
                                              decorationThickness: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (entry.isNotified)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Icon(Icons.notifications_active_rounded, size: 14, color: cs.primary.withValues(alpha: 0.7)),
                                    ),
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: entry.isDone,
                                      onChanged: (bool? isChecked) async {
                                        final isNowDone = isChecked ?? false;

                                        if (isNowDone && !entry.isDone) {
                                          if (entry.coinsAwarded == 0) {
                                            await ref
                                                .read(rewardsProvider.notifier)
                                                .awardPlannerTaskCompletion(
                                                    entry.copyWith(
                                              isDone: true,
                                              isRewarded: true,
                                            ));
                                          } else {
                                            await FirestoreService.instance
                                                .saveTask(entry.copyWith(
                                              isDone: true,
                                              isRewarded: true,
                                            ));
                                          }
                                        } else if (!isNowDone &&
                                            entry.isDone) {
                                          if (entry.coinsAwarded > 0) {
                                            await ref
                                                .read(rewardsProvider.notifier)
                                                .revokePlannerTaskCompletion(
                                                    entry.copyWith(
                                              isDone: false,
                                              isRewarded: false,
                                            ));
                                          } else {
                                            await FirestoreService.instance
                                                .saveTask(entry.copyWith(
                                              isDone: false,
                                              isRewarded: false,
                                            ));
                                          }
                                        }
                                        syncNativeAlarms(ref);
                                      },
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(79, 0, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.access_time_rounded, size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Duration: ${_formatTimeString(entry.startTime)} - ${_formatTimeString(entry.endTime)}',
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                ),
                                if (entry.isTimeLocked) ...[
                                  const SizedBox(width: 12),
                                  Icon(Icons.lock_rounded, size: 14, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text('Fixed', style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                                ]
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.sync_rounded, size: 14, color: cs.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Repeats: ${entry.repeatInterval.name.toUpperCase()}',
                                  style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                                      builder: (_) => UncontrolledProviderScope(
                                        container: ProviderScope.containerOf(context),
                                        child: AddTaskSheet(initialEntry: entry),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.edit_rounded, size: 14),
                                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ), // <-- Missing Bracket 1: Closes the inner Container
      ), // <-- Missing Bracket 2: Closes the ClipRRect
    );
  }
}

void syncNativeAlarms(WidgetRef ref) {
  Future.microtask(() {
    final currentDayTasks = ref.read(selectedDayEntriesProvider);
    final totalToday = currentDayTasks.length;
    final pendingToday = currentDayTasks.where((t) => !t.isDone).length;
    
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final pendingYesterday = currentDayTasks
        .where((t) => !t.isDone && t.startTime.isBefore(todayStart))
        .length;
    
    ref.read(notificationSettingsProvider.notifier).syncBriefingPayloads(totalToday, pendingToday, pendingYesterday);
  });
}