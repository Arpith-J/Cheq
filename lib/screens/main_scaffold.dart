// lib/screens/main_scaffold.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/coins_provider.dart';
import 'todo_list_screen.dart';
import 'daily_planner_screen.dart';
import 'rewards_screen.dart';

// ---------------------------------------------------------------------------
// MainScaffold
// ---------------------------------------------------------------------------

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _selectedIndex = 0;

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
    final coinCount = ref.watch(coinsProvider); // live — rebuilds on change
    final theme     = Theme.of(context);
    final cs        = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,

      // ── AppBar ─────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor:    cs.surface,
        surfaceTintColor:   Colors.transparent,
        shadowColor:        cs.shadow.withOpacity(0.08),
        elevation:          0,
        scrolledUnderElevation: 1,
        titleSpacing:       4,

        // Left — profile avatar
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: _ProfileAvatar(photoUrl: user?.photoURL),
          ),
        ),
        leadingWidth: 56,

        // Centre — dynamic tab title
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _tabs[_selectedIndex].label,
            key: ValueKey(_selectedIndex),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight:   FontWeight.w700,
              color:        cs.onSurface,
              letterSpacing: -0.4,
            ),
          ),
        ),

        // Right — coin pill
        actions: [
          _CoinPill(coinCount: coinCount),
          const SizedBox(width: 16),
        ],
      ),

      // ── Body — IndexedStack preserves scroll state per tab ──────────────
      body: IndexedStack(
        index:    _selectedIndex,
        children: _screens,
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({this.photoUrl});

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
          errorBuilder: (_, __, ___) => Icon(
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
// _CoinPill
// ---------------------------------------------------------------------------

class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.coinCount});

  final int coinCount;

  /// Compact display: 1200 → "1.2k" | 1,500,000 → "1.5M"
  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),           // warm amber surface
        borderRadius: BorderRadius.circular(999), // perfect capsule
        border: Border.all(
          color: const Color(0xFFFFD54F).withOpacity(0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:      const Color(0xFFFFD54F).withOpacity(0.22),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.monetization_on_rounded,
            size:  18,
            color: Color(0xFFFFA000), // amber gold
          ),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end:   Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              _format(coinCount),
              key: ValueKey(coinCount),            // triggers AnimatedSwitcher
              style: const TextStyle(
                fontSize:      14,
                fontWeight:    FontWeight.w700,
                color:         Color(0xFF6D4C00),  // deep amber-brown
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
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