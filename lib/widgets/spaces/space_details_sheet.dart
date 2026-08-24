// lib/widgets/spaces/space_details_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/space_model.dart';
import '../../providers/space_members_provider.dart';

/// Bottom sheet surfaced by tapping the AppBar title of a Space. Shows the
/// group's identity (name + creation date), the shareable join code with a
/// one-tap copy action, and the live member roster resolved through
/// [spaceMembersProvider]. Read-only by design — membership management stays
/// in the AppBar overflow menu.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final createdOn = space.createdAt;
    final membersAsync = ref.watch(spaceMembersProvider(space.id));

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
  const _MemberTile({required this.name, required this.isOwner});

  final String name;
  final bool isOwner;

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
        ],
      ),
    );
  }
}
