// lib/screens/main_scaffold.dart

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo_list_screen.dart';
import 'daily_planner_screen.dart';
import 'rewards_screen.dart';
import '../providers/coins_provider.dart';
import '../widgets/app_side_drawer.dart';

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
      label:      'Garden',
      icon:       Icons.local_florist_outlined,
      activeIcon: Icons.local_florist_rounded,
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
              _selectedIndex == 0 ? 'Todo' : (_selectedIndex == 1 ? 'Planner' : 'Garden'),
              style: const TextStyle(fontWeight: FontWeight.bold), 
            ),
          ),
        ),

        // Right — context-aware coin pill. Always rendered so it can flash on
        // balance changes; visibility is driven internally (Rewards tab keeps
        // it pinned visible, Todo/Planner hide it except for flashes).
        actions: [
          _CoinPill(selectedIndex: _selectedIndex),
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

// ---------------------------------------------------------------------------
// _CoinPill — context-aware coin balance in the AppBar
// ---------------------------------------------------------------------------
//
// Permanently visible on the Rewards/Garden tab (index 2). On the To-Do and
// Planner tabs it stays hidden and only flashes in temporarily whenever the
// live coin balance changes, fading back out after 2 seconds.

class _CoinPill extends ConsumerStatefulWidget {
  const _CoinPill({required this.selectedIndex});

  final int selectedIndex;

  @override
  ConsumerState<_CoinPill> createState() => _CoinPillState();
}

class _CoinPillState extends ConsumerState<_CoinPill>
    with SingleTickerProviderStateMixin {
  static const int _rewardsTabIndex = 2;

  late final AnimationController _controller;
  late final Animation<double>   _opacity;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.selectedIndex == _rewardsTabIndex ? 1.0 : 0,
    );
    _opacity = _controller;
  }

  @override
  void didUpdateWidget(_CoinPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == _rewardsTabIndex) {
      // Rewards tab — force fully visible.
      _hideTimer?.cancel();
      _controller.value = 1.0;
    } else if (oldWidget.selectedIndex == _rewardsTabIndex) {
      // Left the Rewards tab — fade back to hidden.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _flash() {
    if (!mounted) return;
    _hideTimer?.cancel();
    _controller.forward(from: 0);
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && widget.selectedIndex != _rewardsTabIndex) {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(coinsProvider).value ?? 0;

    ref.listen<AsyncValue<int>>(coinsProvider, (previous, next) {
      final prev = previous?.value;
      final curr = next.value;
      if (prev == null || curr == null || curr == prev) return;
      // Only flash when off the Rewards tab — it is always visible there.
      if (widget.selectedIndex != _rewardsTabIndex) _flash();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    const gold = Color(0xFFFFD54F);
    final onGold = isDark ? const Color(0xFFB8860B) : const Color(0xFF6D4C00);

    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: gold.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✨', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                _format(coins),
                key: ValueKey<int>(coins),
                style: TextStyle(
                  color: onGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Standard comma-separated number formatting, e.g. 9500 -> '9,500'.
  String _format(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
}