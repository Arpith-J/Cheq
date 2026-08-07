// lib/widgets/garden_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/garden_plot_model.dart';
import '../providers/rewards_provider.dart';

/// Total number of plots in the garden grid.
const int gardenPlotCount = 12;

/// Growth threshold: under 1 day → seedling, under 3 days → sapling,
/// 3+ days → full tree.
const Duration _seedlingThreshold = Duration(days: 1);
const Duration _saplingThreshold = Duration(days: 3);

const Map<String, String> _seedNames = {
  'pine': 'Pine Seed',
  'oak': 'Oak Seed',
};

const Map<String, String> _treeEmojis = {
  'pine': '🌲',
  'oak': '🌳',
};

// ---------------------------------------------------------------------------
// GardenTab — Forest-style grid of plantable plots
// ---------------------------------------------------------------------------

class GardenTab extends ConsumerWidget {
  const GardenTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userStreamProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemCount: gardenPlotCount,
        itemBuilder: (context, i) {
          return _GardenPlotTile(
            index: i,
            plot: _plotForIndex(user.garden, i),
          );
        },
      ),
    );
  }

  GardenPlotModel? _plotForIndex(List<GardenPlotModel> garden, int index) {
    for (final plot in garden) {
      if (plot.gridIndex == index) return plot;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Single plot — dirt when empty, growing plant when planted
// ---------------------------------------------------------------------------

class _GardenPlotTile extends ConsumerWidget {
  const _GardenPlotTile({required this.index, required this.plot});

  final int index;
  final GardenPlotModel? plot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plot = this.plot;

    if (plot == null) {
      return _EmptyPlot(onTap: () => _showSeedPicker(context, ref));
    }

    final (emoji, size) = _growthIcon(plot);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3A7D44).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2E6B37).withValues(alpha: 0.5),
        ),
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size)),
      ),
    );
  }

  /// Returns the emoji + font size for a plot's current growth stage.
  (String, double) _growthIcon(GardenPlotModel plot) {
    final age = DateTime.now().difference(plot.plantedAt);
    if (age < _seedlingThreshold) return ('🌱', 20);
    if (age < _saplingThreshold) return ('🌿', 26);
    return (_treeEmojis[plot.seedType] ?? '🌳', 34);
  }

  void _showSeedPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Plant a Seed',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              for (final entry in seedCosts.entries) ...[
                ListTile(
                  leading: Text(
                    _treeEmojis[entry.key] ?? '🌱',
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(
                    _seedNames[entry.key] ?? entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${entry.value} ✨'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final ok = await ref
                        .read(rewardsProvider.notifier)
                        .plantSeed(index, entry.key, entry.value);
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Not enough coins to plant that seed.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty brown dirt plot
// ---------------------------------------------------------------------------

class _EmptyPlot extends StatelessWidget {
  const _EmptyPlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF8B5A2B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF5D452A).withValues(alpha: 0.6),
            ),
          ),
          child: const Center(
            child: Icon(Icons.add, size: 26, color: Color(0x66FFFFFF)),
          ),
        ),
      ),
    );
  }
}
