import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../providers/notification_settings_provider.dart';
import '../../providers/planner_provider.dart';

class AddTaskSheet extends ConsumerStatefulWidget {
  final PlannerModel? initialEntry;

  const AddTaskSheet({super.key, this.initialEntry});

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  late final TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();

  bool _isSaving = false;
  bool _notifyMe = false;
  bool _isTimeLocked = false;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late RepeatInterval _repeatInterval;
  Duration? _customInterval;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;

    _titleCtrl = TextEditingController(text: entry?.title ?? '');
    _notifyMe = entry?.isNotified ?? false;
    _repeatInterval = entry?.repeatInterval ?? RepeatInterval.none;
    _customInterval = entry?.customInterval;
    _isTimeLocked = entry?.isTimeLocked ?? false;

    if (entry != null) {
      _startTime = TimeOfDay.fromDateTime(entry.startTime);
      _endTime = TimeOfDay.fromDateTime(entry.endTime);
    } else {
      _startTime = TimeOfDay.now();
      _endTime = TimeOfDay(
        hour: (_startTime.hour + 1) % 24,
        minute: _startTime.minute,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startTime = picked;
        final startMins = picked.hour * 60 + picked.minute;
        final endMins = _endTime.hour * 60 + _endTime.minute;
        if (endMins <= startMins) {
          final advanced = startMins + 60;
          _endTime = TimeOfDay(
            hour: (advanced ~/ 60) % 24,
            minute: advanced % 60,
          );
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _showCustomIntervalDialog() async {
    final ctrl = TextEditingController();
    final steps = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Interval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Repeat every X days',
            hintText: 'e.g. 3',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    ctrl.dispose();

    if (steps != null && steps > 0) {
      setState(() => _customInterval = Duration(days: steps));
    } else {
      setState(() {
        _repeatInterval = RepeatInterval.none;
        _customInterval = null;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving || _titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }

    final entry = widget.initialEntry;
    final isExistingRecurring = entry != null && entry.repeatGroupId != null;
    
    int editScope = 0; 

    if (isExistingRecurring) {
      // 1. Intercept repeat changes so we don't ask unnecessarily
      if (entry.repeatInterval != _repeatInterval) {
        editScope = 2; // Automatically target future tasks to cleanly rebuild or delete them
      } else {
        // Only ask if repeat interval is the SAME but other metadata changed
        final choice = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Edit Repeating Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: const Text('Do you want to apply these changes to this task only, or all future tasks in this series?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
                onPressed: () => Navigator.pop(ctx, 1),
                child: const Text('This Only'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                onPressed: () => Navigator.pop(ctx, 2),
                child: const Text('All Future'),
              ),
            ],
          ),
        );

        if (choice == null || choice == 0) return; 
        editScope = choice;
      }
    }

    setState(() => _isSaving = true);

    try {
      final day = ref.read(selectedDayProvider);
      DateTime toDateTime(TimeOfDay t, DateTime d) => DateTime(d.year, d.month, d.day, t.hour, t.minute);

      final String baseId = entry?.id ?? 'entry_${DateTime.now().millisecondsSinceEpoch}';
      
      String? groupId = entry?.repeatGroupId;
      
      // 2. Detach from group if repeat is now turned off
      if (_repeatInterval == RepeatInterval.none && editScope == 2) {
        groupId = null; 
      } else if (groupId == null && _repeatInterval != RepeatInterval.none) {
        groupId = 'grp_$baseId';
      }

      List<PlannerModel> tasksToSave = [];
      DateTime currentDay = day;

      // 3. FIX: Only generate 7 instances if it is ACTUALLY repeating
      int instanceCount = 1;
      if (_repeatInterval != RepeatInterval.none && (editScope == 2 || editScope == 0)) {
        instanceCount = 7;
      }

      for (int i = 0; i < instanceCount; i++) {
        final startDt = toDateTime(_startTime, currentDay);
        final endDt = toDateTime(_endTime, currentDay);
        
        final instanceId = (editScope == 1 || i == 0) ? baseId : '${baseId}_$i';

        final entryToSave = PlannerModel(
          id: instanceId,
          title: _titleCtrl.text.trim(),
          startTime: startDt,
          endTime: endDt,
          isDone: i == 0 ? (entry?.isDone ?? false) : false,
          isNotified: _notifyMe,
          isTimeLocked: _isTimeLocked,
          repeatInterval: editScope == 1 ? entry!.repeatInterval : _repeatInterval,
          customInterval: editScope == 1 ? entry!.customInterval : _customInterval,
          repeatGroupId: groupId,
        );
        
        tasksToSave.add(entryToSave);

        if (_notifyMe) {
          final rawDigits = instanceId.replaceAll(RegExp(r'[^0-9]'), '');
          final parsedInt = int.tryParse(rawDigits);
          final int stableNotificationId = parsedInt != null ? (parsedInt % 2147483647) : instanceId.hashCode;
          
          await NotificationService.instance.cancelNotification(stableNotificationId);
          unawaited(NotificationService.instance.scheduleNotification(
            id: stableNotificationId,
            title: '$appName Reminder', 
            body: entryToSave.title,
            scheduledTime: startDt,
          ));
        }

        if (_repeatInterval == RepeatInterval.daily) {
          currentDay = currentDay.add(const Duration(days: 1));
        } else if (_repeatInterval == RepeatInterval.weekly) {
          currentDay = currentDay.add(const Duration(days: 7));
        } else if (_repeatInterval == RepeatInterval.monthly) {
          currentDay = DateTime(currentDay.year, currentDay.month + 1, currentDay.day);
        } else if (_repeatInterval == RepeatInterval.custom && _customInterval != null) {
          currentDay = currentDay.add(_customInterval!);
        }
      }

      // 4. FIX: Safely use the old group ID to delete the old future tasks
      if (editScope == 2 && entry != null) {
        await FirestoreService.instance.deleteRecurringTaskGroup(entry.repeatGroupId!, entry.startTime);
      }

      unawaited(FirestoreService.instance.saveTasksBatch(tasksToSave));
      
      // Native Alarm Sync
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

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error inside save calculation routine: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
        child: Padding(
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
                    widget.initialEntry != null ? 'Edit Task' : 'New Task',
                    style:
                        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleCtrl,
                focusNode: _titleFocus,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'What do you need to do?',
                  hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeTile(
                      label: 'Start',
                      time: _startTime,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeTile(
                      label: 'End',
                      time: _endTime,
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      size: 18,
                      color: _repeatInterval != RepeatInterval.none
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    Text('Repeat',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const Spacer(),
                    DropdownButton<RepeatInterval>(
                      value: _repeatInterval,
                      underline: const SizedBox(),
                      dropdownColor: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      onChanged: (RepeatInterval? newVal) {
                        if (newVal == null) return;
                        setState(() => _repeatInterval = newVal);
                        if (newVal == RepeatInterval.custom) {
                          _showCustomIntervalDialog();
                        } else {
                          _customInterval = null;
                        }
                      },
                      items: RepeatInterval.values.map((val) {
                        String display = val.name.toUpperCase();
                        if (val == RepeatInterval.custom && _customInterval != null) {
                          display = '${_customInterval!.inDays} DAYS';
                        }
                        return DropdownMenuItem(
                          value: val,
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isTimeLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 18,
                      color: _isTimeLocked ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    const Text('Lock Time (Fixed)'),
                    const Spacer(),
                    Switch.adaptive(
                      value: _isTimeLocked,
                      onChanged: (v) => setState(() => _isTimeLocked = v),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _notifyMe ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                      size: 18,
                      color: _notifyMe ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 10),
                    const Text('Notify me'),
                    const Spacer(),
                    Switch.adaptive(
                      value: _notifyMe,
                      onChanged: (v) => setState(() => _notifyMe = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text =
        '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}:${time.minute.toString().padLeft(2, '0')} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}