// lib/screens/main_scaffold.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo_list_screen.dart';
import 'daily_planner_screen.dart';
import 'rewards_screen.dart';
import '../widgets/app_side_drawer.dart';
import '../widgets/coin_flash_overlay.dart';

// ---------------------------------------------------------------------------
// MainScaffold
// ---------------------------------------------------------------------------

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _selectedIndex = 1;

  // IndexedStack children — never re-instantiated on tab switch
  static const List<Widget> _screens = [
    TodoListScreen(),
    DailyPlannerScreen(),
    RewardsScreen(),
  ];

  static const List<_TabItem> _tabs = [
    _TabItem(
      label:      'To-Do',
      icon:       Icons.checklist_rounded,
      activeIcon: Icons.checklist_rtl_rounded,
    ),
    _TabItem(
      label:      'Planner',
      icon:       Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
    ),
    _TabItem(
      label:      'Rewards',
      icon:       Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final user      = FirebaseAuth.instance.currentUser;
    final theme     = Theme.of(context);
    final cs        = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      drawer: const AppSideDrawer(),

      // ── AppBar ─────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor:    cs.surface,
        surfaceTintColor:   Colors.transparent,
        shadowColor:        cs.shadow.withValues(alpha: 0.08),
        elevation:          0,
        scrolledUnderElevation: 1,
        titleSpacing:       4,

        // Left — profile avatar
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: Builder(
              builder: (innerContext) {
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    // Open the side window via the local Scaffold drawer handle
                    Scaffold.of(innerContext).openDrawer();
                  },
                  child: ProfileAvatar(photoUrl: user?.photoURL),
                );
              },
            ),
          ),
        ),
        leadingWidth: 56,

        // Centre — dynamic tab title
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.2), // Slides up slightly
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          // The ValueKey is CRITICAL. It tells Flutter the text actually changed so it triggers the animation
          child: SizedBox(
            key: ValueKey<int>(_selectedIndex),
            width: 120, // Wide enough to hold 'Planner' and 'Rewards' without wrapping
            child: Text(
              _selectedIndex == 0 ? 'Todo' : (_selectedIndex == 1 ? 'Planner' : 'Rewards'),
              style: const TextStyle(fontWeight: FontWeight.bold), 
            ),
          ),
        ),

        // Right — reserved spacing
        actions: const [SizedBox(width: 16)],
      ),

      // ── Body — IndexedStack preserves scroll state per tab ──────────────
      body: Stack(
        children: [
          IndexedStack(
            index:    _selectedIndex,
            children: _screens,
          ),
          // Transient "+N Coins" flash in the top-right corner.
          const Positioned(
            top: 8,
            right: 12,
            child: CoinFlashOverlay(),
          ),
        ],
      ),

      // ── Bottom Navigation Bar (Material 3) ──────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex:        _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor:      cs.surface,
        surfaceTintColor:     Colors.transparent,
        indicatorColor:       cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon:         Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon, color: cs.primary),
              label:        tab.label,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ProfileAvatar
// ---------------------------------------------------------------------------

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (photoUrl == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer,
        child: Icon(Icons.person_rounded, size: 20, color: cs.primary),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: cs.primaryContainer,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width:  36,
          height: 36,
          fit:    BoxFit.cover,
          // Graceful fallback if the Google CDN photo fails to load
          errorBuilder: (_, _, _) => Icon(
            Icons.person_rounded,
            size:  20,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TabItem — internal tab metadata
// ---------------------------------------------------------------------------

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String   label;
  final IconData icon;
  final IconData activeIcon;
}