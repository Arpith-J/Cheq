// lib/widgets/spaces/group_task_sheet.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';

/// Bottom sheet for scheduling a new time-blocked task on the shared Group
/// Planner timeline. Mirrors the personal planner's `AddTaskSheet` styling but
/// stays intentionally slim: a title, a date, start/end times, and an optional
/// assignee. Saving writes straight into `spaces/{spaceId}/tasks` so every
/// member's Group Planner timeline updates in near-real-time.
class GroupTaskSheet extends ConsumerStatefulWidget {
  const GroupTaskSheet({super.key, required this.spaceId, this.initialEntry});

  /// The owning Space — the task is stored under `spaces/{spaceId}/tasks`.
  final String spaceId;

  /// When provided the sheet edits this existing task instead of creating a
  /// new one: the fields are pre-filled and [FirestoreService.saveGroupTask]
  /// keeps the original id/createdAt so ordering and identity are preserved.
  final PlannerModel? initialEntry;

  @override
  ConsumerState<GroupTaskSheet> createState() => _GroupTaskSheetState();
}

class _GroupTaskSheetState extends ConsumerState<GroupTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _titleFocus = FocusNode();

  bool _isSaving = false;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _assignedTo;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    if (entry != null) {
      _titleCtrl.text = entry.title;
      _date = entry.startTime;
      _startTime = TimeOfDay.fromDateTime(entry.startTime);
      _endTime = TimeOfDay.fromDateTime(entry.endTime);
      _assignedTo = entry.assignedTo;
    } else {
      _date = DateTime.now();
      _startTime = TimeOfDay.now();
      final endMinutes = _startTime.hour * 60 + _startTime.minute + 60;
      _endTime = TimeOfDay(hour: endMinutes ~/ 60 % 24, minute: endMinutes % 60);
      _assignedTo = FirebaseAuth.instance.currentUser?.uid;
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
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
        final startMinutes = picked.hour * 60 + picked.minute;
        final endMinutes = _endTime.hour * 60 + _endTime.minute;
        if (endMinutes <= startMinutes) {
          final advanced = startMinutes + 60;
          _endTime = TimeOfDay(
            hour: advanced ~/ 60 % 24,
            minute: advanced % 60,
          );
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_isSaving || _titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);

    try {
      final start = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );
      var end = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _endTime.hour,
        _endTime.minute,
      );
      if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));

      final existing = widget.initialEntry;
      final task = PlannerModel(
        id: existing?.id ?? 'group_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleCtrl.text.trim(),
        startTime: start,
        endTime: end,
        // Shared schedule blocks are fixed windows, immune to any personal
        // liquid-rebalance pass.
        isTimeLocked: true,
        groupId: widget.spaceId,
        assignedTo: _assignedTo,
        isDone: existing?.isDone ?? false,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await FirestoreService.instance.saveGroupTask(widget.spaceId, task);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Failed to schedule group task: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final membersAsync = ref.watch(spaceMembersProvider(widget.spaceId));
    final memberNames = Map<String, String>.from(membersAsync.value ?? const {});
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final myName = FirebaseAuth.instance.currentUser?.displayName;
    if (myUid != null && !memberNames.containsKey(myUid)) {
      memberNames[myUid] = (myName == null || myName.isEmpty) ? 'You' : myName;
    }

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
                      widget.initialEntry != null
                          ? 'Edit Task'
                          : 'Schedule Task',
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
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'What should the group do?',
                    hintStyle:
                        TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
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
                const SizedBox(height: 12),
                // ── ASSIGN TO (maps to `assignedTo`) ──
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_rounded,
                        size: 18,
                        color: _assignedTo != null
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Assign To',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      DropdownButton<String?>(
                        value: _assignedTo,
                        underline: const SizedBox(),
                        dropdownColor: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: _isSaving
                            ? null
                            : (String? newVal) =>
                                setState(() => _assignedTo = newVal),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Everyone'),
                          ),
                          for (final uid in memberNames.keys)
                            DropdownMenuItem<String?>(
                              value: uid,
                              child: Text(
                                memberNames[uid] ?? 'Member',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // ── DATE ──
                _GroupDateTile(
                  date: _date,
                  onTap: _isSaving ? null : _pickDate,
                ),
                const SizedBox(height: 12),
                // ── START / END TIMES ──
                Row(
                  children: [
                    Expanded(
                      child: _GroupTimeTile(
                        label: 'Start',
                        time: _startTime,
                        onTap: _isSaving ? null : () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GroupTimeTile(
                        label: 'End',
                        time: _endTime,
                        onTap:
                            _isSaving ? null : () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date tile — taps open a date picker defaulting to today
// ---------------------------------------------------------------------------

class _GroupDateTile extends StatelessWidget {
  const _GroupDateTile({required this.date, this.onTap});

  final DateTime date;
  final VoidCallback? onTap;

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            Text('Date', style: TextStyle(color: cs.onSurfaceVariant)),
            Text(
              '${_weekdays[date.weekday - 1]}, '
              '${_months[date.month - 1]} ${date.day}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Time tile — mirrors the personal planner's start/end pickers
// ---------------------------------------------------------------------------

class _GroupTimeTile extends StatelessWidget {
  const _GroupTimeTile({
    required this.label,
    required this.time,
    this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text =
        '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}:'
        '${time.minute.toString().padLeft(2, '0')} '
        '${time.period == DayPeriod.am ? 'AM' : 'PM'}';

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
