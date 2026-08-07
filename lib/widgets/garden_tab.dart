// lib/widgets/garden_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/garden_plot_model.dart';
import '../providers/rewards_provider.dart';

/// Total number of plots in the garden (4 seasons × 3 plots each).
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
// Seasonal quadrant metadata
// ---------------------------------------------------------------------------

class _SeasonSpec {
  const _SeasonSpec({
    required this.name,
    required this.emoji,
    required this.deco,
    required this.color,
    required this.borderColor,
    required this.startIndex,
  });

  final String name;
  final String emoji;

  /// Decorative glyph rendered on the extra soil tile of the 2x2 grid.
  final String deco;
  final Color color;
  final Color borderColor;

  /// First global `gridIndex` owned by this season (3 consecutive plots).
  final int startIndex;
}

/// Quadrant layout order: top row Spring (left) + Autumn (right),
/// bottom row Summer (left) + Winter (right).
const List<_SeasonSpec> _seasons = [
  _SeasonSpec(
    name: 'Spring',
    emoji: '🌸',
    deco: '🌼',
    color: Color(0xFF81C784),
    borderColor: Color(0xFF2E7D32),
    startIndex: 0,
  ),
  _SeasonSpec(
    name: 'Autumn',
    emoji: '🍂',
    deco: '🍁',
    color: Color(0xFFE6A873),
    borderColor: Color(0xFFB45309),
    startIndex: 6,
  ),
  _SeasonSpec(
    name: 'Summer',
    emoji: '☀️',
    deco: '🍉',
    color: Color(0xFFFFB74D),
    borderColor: Color(0xFFE65100),
    startIndex: 3,
  ),
  _SeasonSpec(
    name: 'Winter',
    emoji: '❄️',
    deco: '☃️',
    color: Color(0xFF64B5F6),
    borderColor: Color(0xFF1565C0),
    startIndex: 9,
  ),
];

// ---------------------------------------------------------------------------
// GardenTab — zoomable 2x2 seasonal garden canvas
// ---------------------------------------------------------------------------

class GardenTab extends ConsumerWidget {
  const GardenTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userStreamProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) => InteractiveViewer(
        // Infinite boundary + generous zoom range: the whole land can be
        // panned around and scaled freely.
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.5,
        maxScale: 3.0,
        constrained: false,
        child: SizedBox(
          width: 480,
          height: 800,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Top row: Spring | Autumn ──────────────────────────────
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _SeasonQuadrant(
                          season: _seasons[0],
                          garden: user.garden,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SeasonQuadrant(
                          season: _seasons[1],
                          garden: user.garden,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Bottom row: Summer | Winter ───────────────────────────
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _SeasonQuadrant(
                          season: _seasons[2],
                          garden: user.garden,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SeasonQuadrant(
                          season: _seasons[3],
                          garden: user.garden,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single season quadrant — a fenced 2x2 plot grid
// ---------------------------------------------------------------------------

class _SeasonQuadrant extends StatelessWidget {
  const _SeasonQuadrant({required this.season, required this.garden});

  final _SeasonSpec season;
  final List<GardenPlotModel> garden;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: season.color.withValues(alpha: isDark ? 0.20 : 0.40),
        borderRadius: BorderRadius.circular(20),
        // Thick stylized border doubles as the "fence" around the field.
        border: Border.all(
          color: season.borderColor.withValues(alpha: isDark ? 0.55 : 0.85),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Season header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(season.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                season.name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.4,
                  color: season.borderColor.withValues(alpha: isDark ? 0.95 : 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 2x2 plot grid — 3 owned plots + 1 seasonal decorative tile
          Expanded(
            child: Center(
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
                children: [
                  for (var local = 0; local < 3; local++)
                    _GardenPlotTile(
                      index: season.startIndex + local,
                      plot: _plotForIndex(
                        garden,
                        season.startIndex + local,
                      ),
                    ),
                  _SeasonDecorativeTile(season: season),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seasonal decorative soil tile (fills the 4th cell of each 2x2 grid)
// ---------------------------------------------------------------------------

class _SeasonDecorativeTile extends StatelessWidget {
  const _SeasonDecorativeTile({required this.season});

  final _SeasonSpec season;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: season.color.withValues(alpha: isDark ? 0.10 : 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: season.borderColor.withValues(alpha: isDark ? 0.30 : 0.45),
        ),
      ),
      child: Center(
        child: Text(
          season.deco,
          style: TextStyle(
            fontSize: 24,
            color: season.borderColor.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GardenPlotModel? _plotForIndex(List<GardenPlotModel> garden, int index) {
  for (final plot in garden) {
    if (plot.gridIndex == index) return plot;
  }
  return null;
}
