// lib/screens/main_scaffold.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo_list_screen.dart';
import 'daily_planner_screen.dart';
import 'spaces_screen.dart';
import '../providers/coins_provider.dart';
import '../providers/local_notes_provider.dart';
import '../providers/rewards_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/app_side_drawer.dart';
import '../widgets/flashing_coin_pill.dart';

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

  @override
  void initState() {
    super.initState();
    // Frame-dependent: reading/invalidating Riverpod providers is not allowed
    // synchronously inside build(), so hydration runs right after the first
    // frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateCloudData();
      ref.read(localNotesProvider.notifier).loadFromDisk();
    });
  }

  /// Explicitly fetches the user's `users/{uid}` document from Firestore and
  /// hydrates the local economy/stats/badge providers with the cloud data.
  ///
  /// On a fresh install the FirebaseAuth session restores asynchronously, so
  /// the stream providers may have been built with a null user and cached a
  /// permanent 0/empty value. This seeds `rewardsProvider` from the fetched
  /// [UserModel] and forces `coinsProvider` + `userStreamProvider` to
  /// re-subscribe keyed to the signed-in user BEFORE the Trophy Room, Stats
  /// and Planner UI settle on their first render.
  Future<void> _hydrateCloudData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 1. Force the live streams to (re)subscribe with the signed-in user.
      ref.invalidate(coinsProvider);
      ref.invalidate(userStreamProvider);

      // 2. Explicit one-shot fetch of the cloud UserModel document.
      final cloudModel =
          await FirestoreService.instance.getUserModel(user.uid);
      if (cloudModel == null) return;

      // 3. Seed the coins/badges/constellation/streak notifier immediately so
      //    no screen ever renders a stale zero before the stream catches up.
      ref.read(rewardsProvider.notifier).hydrateFromCloud(cloudModel);
    } catch (e) {
      debugPrint('Cloud data hydration failed: $e');
    }
  }

  // IndexedStack children — never re-instantiated on tab switch
  static const List<Widget> _screens = [
    TodoListScreen(),
    DailyPlannerScreen(),
    SpacesScreen(),
  ];

  static const List<_TabItem> _tabs = [
    _TabItem(
      label:      'ToDo',
      icon:       Icons.checklist_rounded,
      activeIcon: Icons.checklist_rtl_rounded,
    ),
    _TabItem(
      label:      'Planner',
      icon:       Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
    ),
    _TabItem(
      label:      'Spaces',
      icon:       Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
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
            width: 120, // Wide enough to hold 'Planner' and 'Spaces' without wrapping
            child: Text(
              _selectedIndex == 0 ? 'Todo' : (_selectedIndex == 1 ? 'Planner' : 'Spaces'),
              style: const TextStyle(fontWeight: FontWeight.bold), 
            ),
          ),
        ),

        // Right — coin balance pill. Hidden by default and only flashing for
        // 2 seconds when the balance increases, so the earned economy stays
        // out of sight on the main tabs (Rewards lives in the side drawer and
        // shows the permanently visible CoinPill on Bundles/Constellation).
        actions: [
          const FlashingCoinPill(),
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