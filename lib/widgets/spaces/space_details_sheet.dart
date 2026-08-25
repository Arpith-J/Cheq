// lib/widgets/spaces/space_details_sheet.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/space_model.dart';
import '../../providers/space_members_provider.dart';
import '../../services/firestore_service.dart';

/// Bottom sheet surfaced by tapping the AppBar title of a Space. Shows the
/// group's identity (name + creation date), the shareable join code with a
/// one-tap copy action, and the live member roster resolved through
/// [spaceMembersProvider]. When the viewer owns the Space, every other member
/// row gains a Remove action (confirmation-gated `FieldValue.arrayRemove`).
class SpaceDetailsSheet extends ConsumerWidget {
  const SpaceDetailsSheet({super.key, required this.space});

  /// The Space whose details are rendered.
  final SpaceModel space;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  void _copyJoinCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: space.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Owner-only member removal. Asks for confirmation, then pulls [uid] off
  /// the Space document's `members` array via `FieldValue.arrayRemove`. Every
  /// watcher (roster, member count, assignee pickers) refreshes live because
  /// they all stream from the same Space document.
  Future<void> _confirmRemoveMember(
    BuildContext context,
    String uid,
    String name,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove $name from "${space.name}"? They can rejoin later using '
          'the join code.',
        ),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirestoreService.instance.removeMemberFromSpace(space.id, uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name removed from ${space.name}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not remove $name. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final createdOn = space.createdAt;
    final membersAsync = ref.watch(spaceMembersProvider(space.id));

    // Only the owner may manage the roster; the owner row itself can never be
    // removed from their own Space.
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final iAmOwner =
        myUid != null && myUid.isNotEmpty && space.createdBy == myUid;

    return SafeArea(
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
              // ── IDENTITY ──
              Text(
                space.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Created ${_months[createdOn.month - 1]} '
                    '${createdOn.day}, ${createdOn.year}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // ── JOIN CODE ──
              Text(
                'JOIN CODE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Text(
                      space.roomCode,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: cs.primary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy join code',
                      onPressed: () => _copyJoinCode(context),
                      icon: Icon(Icons.copy, size: 20, color: cs.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ── MEMBERS ──
              Text(
                'MEMBERS (${space.members.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              membersAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Could not load members.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                data: (names) => Column(
                  children: [
                    for (final entry in names.entries)
                      _MemberTile(
                        name: entry.value,
                        isOwner: entry.key == space.createdBy,
                        // Owners get a Remove action on every row except
                        // their own.
                        onRemove:
                            (iAmOwner && entry.key != space.createdBy)
                                ? () => _confirmRemoveMember(
                                      context,
                                      entry.key,
                                      entry.value,
                                    )
                                : null,
                      ),
                  ],
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
// _MemberTile — avatar + display-name row for a single group member
// ---------------------------------------------------------------------------

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.name, required this.isOwner, this.onRemove});

  final String name;
  final bool isOwner;

  /// Non-null only when the signed-in viewer owns the Space and this row is
  /// another member; renders the Remove action. The owner's own row (and every
  /// row for a non-owner viewer) stays action-free.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Owner',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove member',
              onPressed: onRemove,
              icon: Icon(
                Icons.person_remove_rounded,
                size: 20,
                color: cs.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
