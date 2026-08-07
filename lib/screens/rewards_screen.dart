// lib/screens/rewards_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rewards_provider.dart';
import '../widgets/garden_tab.dart';
import 'constellation_screen.dart';

// ---------------------------------------------------------------------------
// RewardsScreen — Garden & Constellation hub
// ---------------------------------------------------------------------------

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConstellationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userStreamProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (_) => Column(
            children: [
              const TabBar(
                labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  Tab(text: 'Garden'),
                  Tab(text: 'Constellation'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    const GardenTab(),
                    ConstellationView(onFullScreen: _openFullScreen),
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

