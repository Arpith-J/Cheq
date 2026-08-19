// lib/screens/space_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/space_model.dart';
import '../providers/spaces_provider.dart';
import '../widgets/spaces/group_planner_tab.dart';
import '../widgets/spaces/group_reminders_tab.dart';
import '../widgets/spaces/group_todo_tab.dart';

// ---------------------------------------------------------------------------
// SpaceDetailScreen — nested Group workspace
// ---------------------------------------------------------------------------
//
// Visually mirrors the main app scaffold: an AppBar carrying the Space's name
// plus a Material 3 NavigationBar. The bottom navigation is strictly the three
// Group tabs — 'Group To-Do', 'Group Planner' and 'Group Reminders'. All three
// are live: Group To-Do and Group Planner share the `tasks` subcollection while
// Group Reminders streams its own `reminders` subcollection.

class SpaceDetailScreen extends ConsumerStatefulWidget {
  const SpaceDetailScreen({super.key, required this.space});

  final SpaceModel space;

  @override
  ConsumerState<SpaceDetailScreen> createState() => _SpaceDetailScreenState();
}

class _SpaceDetailScreenState extends ConsumerState<SpaceDetailScreen> {
  int _selectedIndex = 0;

  static const List<_GroupTab> _tabs = [
    _GroupTab(
      label: 'Group To-Do',
      icon: Icons.checklist_outlined,
      activeIcon: Icons.checklist_rtl_rounded,
    ),
    _GroupTab(
      label: 'Group Planner',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
    ),
    _GroupTab(
      label: 'Group Reminders',
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
    ),
  ];

  Future<void> _confirmLeave() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Space?'),
        content: Text(
          'You will stop seeing "${widget.space.name}" and its shared tasks.',
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
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref.read(spacesNotifierProvider.notifier).leaveSpace(widget.space.id);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Left "${widget.space.name}".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not leave the Space. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: cs.shadow.withValues(alpha: 0.08),
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.space.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.space.roomCode}  •  ${widget.space.members.length} members',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: cs.onSurface),
            onSelected: (value) {
              if (value == 'leave') _confirmLeave();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Text('Leave Space', style: TextStyle(color: cs.error)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      // IndexedStack preserves each tab's state across switches.
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          GroupTodoTab(spaceId: widget.space.id),
          GroupPlannerTab(spaceId: widget.space.id),
          GroupRemindersTab(spaceId: widget.space.id),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon, color: cs.primary),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GroupTab — metadata for the three Group bottom-navigation tabs
// ---------------------------------------------------------------------------

class _GroupTab {
  const _GroupTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
