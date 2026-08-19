// lib/widgets/spaces/group_reminder_sheet.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/planner_model.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';

/// Bottom sheet for creating a new shared Group Reminder. Styling mirrors the
/// other Space sheets: a title, a single date+time trigger, and an 'Assign To'
/// dropdown. Saving writes straight into `spaces/{spaceId}/reminders` so every
/// member's Group Reminders list updates in near-real-time.
class GroupReminderSheet extends ConsumerStatefulWidget {
  const GroupReminderSheet({super.key, required this.spaceId});

  /// The owning Space — the reminder is stored under `spaces/{spaceId}/reminders`.
  final String spaceId;

  @override
  ConsumerState<GroupReminderSheet> createState() => _GroupReminderSheetState();
}

class _GroupReminderSheetState extends ConsumerState<GroupReminderSheet> {
  final _titleCtrl = TextEditingController();
  final _titleFocus = FocusNode();

  bool _isSaving = false;
  late DateTime _trigger;
  String? _assignedTo;

  @override
  void initState() {
    super.initState();
    // Default the alert trigger to the next round half-hour so the picker
    // starts on a sensible, always-in-the-future time.
    final now = DateTime.now();
    final minute = now.minute >= 30 ? 0 : 30;
    final hour = (now.minute >= 30 ? now.hour + 1 : now.hour) % 24;
    _trigger = DateTime(now.year, now.month, now.day, hour, minute);
    // Reminders default to the whole group ('Everyone' / null).
    _assignedTo = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickTrigger() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _trigger,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_trigger),
    );
    if (time == null || !mounted) return;

    setState(() {
      _trigger = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_isSaving || _titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);

    try {
      // A reminder is a point-in-time alert, so start == end (the exact
      // trigger). That also keeps reminders out of the Group Planner timeline,
      // which only surfaces windows where `endTime.isAfter(startTime)`.
      final reminder = PlannerModel(
        id: 'reminder_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleCtrl.text.trim(),
        startTime: _trigger,
        endTime: _trigger,
        isTimeLocked: true, // the alert trigger is a fixed point in time
        groupId: widget.spaceId,
        assignedTo: _assignedTo,
        createdAt: DateTime.now(),
      );

      await FirestoreService.instance
          .saveGroupReminder(widget.spaceId, reminder);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Failed to schedule group reminder: $e');
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
                      'New Reminder',
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
                    hintText: 'What should the group be reminded of?',
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
                // ── TRIGGER DATE + TIME ──
                _TriggerTile(
                  trigger: _trigger,
                  onTap: _isSaving ? null : _pickTrigger,
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
// Trigger tile — one tap walks through a date picker then a time picker
// ---------------------------------------------------------------------------

class _TriggerTile extends StatelessWidget {
  const _TriggerTile({required this.trigger, this.onTap});

  final DateTime trigger;
  final VoidCallback? onTap;

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
          children: [
            Icon(Icons.alarm_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            const Text('Remind at'),
            const Spacer(),
            Text(
              '${_weekdays[trigger.weekday - 1]}, '
              '${_months[trigger.month - 1]} ${trigger.day} • '
              '${_formatTime(trigger)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
