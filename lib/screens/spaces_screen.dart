// lib/screens/spaces_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/space_model.dart';
import '../providers/spaces_provider.dart';
import 'space_detail_screen.dart';

// ---------------------------------------------------------------------------
// SpacesScreen — collaborative group hub
// ---------------------------------------------------------------------------
//
// Lists the user's joined Spaces, with modals to create a new Space (revealing
// its shareable 6-digit room code) and to join an existing one by code.

class SpacesScreen extends ConsumerStatefulWidget {
  const SpacesScreen({super.key});

  @override
  ConsumerState<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends ConsumerState<SpacesScreen> {
  bool get _isBusy =>
      ref.watch(spacesNotifierProvider).isLoading;

  Future<void> _openCreateSpace() async {
    final nameController = TextEditingController();

    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Space'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Name your Space so your group can find it.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Space name',
                hintText: 'e.g. Weekend Warriors',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(ctx, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create'),
          ),
        ],
      ),
    );

    final name = (submitted ?? '').trim();
    if (name.isEmpty || !mounted) return;

    final space = await ref.read(spacesNotifierProvider.notifier).createSpace(name);
    if (!mounted) return;

    if (space == null) {
      _showMessage('Could not create the Space. Please try again.');
      return;
    }

    await _showRoomCodeDialog(space);
  }

  /// Success dialog after creation — shows the shareable 6-digit code with a
  /// "Copy / Share" action (clipboard; no external share dependency needed).
  Future<void> _showRoomCodeDialog(SpaceModel space) async {
    final cs = Theme.of(context).colorScheme;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${space.name}" created!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this code with your group so they can join:',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                space.roomCode,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: space.roomCode));
              if (!ctx.mounted || !mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Room code copied to clipboard.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy / Share'),
          ),
        ],
      ),
    );
  }

  Future<void> _openJoinSpace() async {
    final codeController = TextEditingController();
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> submit() async {
              final code = codeController.text.trim().toUpperCase();
              if (code.length != 6) {
                setSheetState(() => error = 'Enter the full 6-digit code.');
                return;
              }
              setSheetState(() => error = null);

              final joined = await ref
                  .read(spacesNotifierProvider.notifier)
                  .joinSpace(code);
              if (!mounted || !sheetContext.mounted) return;

              if (joined) {
                Navigator.pop(sheetContext);
                _showMessage('Joined the Space!');
              } else {
                setSheetState(() => error = 'No Space found with that code.');
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.group_add_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Join a Space',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit room code shared by a Space member.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                      UpperCaseTextFormatter(),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'A1B2C3',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) setSheetState(() => error = null);
                    },
                    onSubmitted: (_) => submit(),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : submit,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Join Space'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacesAsync = ref.watch(userSpacesProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text(
            'Spaces',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Collaborate on shared tasks with friends and family.',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.add_box_outlined,
                  title: 'Create Space',
                  subtitle: 'Start a new group.',
                  onTap: _openCreateSpace,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.keyboard_rounded,
                  title: 'Join by Code',
                  subtitle: 'Enter a 6-digit code.',
                  onTap: _openJoinSpace,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'YOUR SPACES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          spacesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Could not load your Spaces.\n$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            data: (spaces) => spaces.isEmpty
                ? _EmptySpaces(cs: cs)
                : Column(
                    children: [
                      for (final space in spaces) ...[
                        _SpaceCard(
                          space: space,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SpaceDetailScreen(space: space),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ActionCard — tappable card for the Create / Join entry points
// ---------------------------------------------------------------------------

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.3,
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
// _SpaceCard — joined Space list entry
// ---------------------------------------------------------------------------

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({required this.space, required this.onTap});

  final SpaceModel space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final memberLabel = space.members.length == 1
        ? '1 member'
        : '${space.members.length} members';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.groups_rounded, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${space.roomCode}  •  $memberLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EmptySpaces — friendly empty state
// ---------------------------------------------------------------------------

class _EmptySpaces extends StatelessWidget {
  const _EmptySpaces({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.groups_2_outlined, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            'No Spaces yet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a Space or join one with a room code to\nstart collaborating.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// UpperCaseTextFormatter — forces room codes to uppercase while typing
// ---------------------------------------------------------------------------

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
