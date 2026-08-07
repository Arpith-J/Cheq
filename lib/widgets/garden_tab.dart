// lib/widgets/garden_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weather_animation/weather_animation.dart';

import '../models/garden_plot_model.dart';
import '../providers/rewards_provider.dart';

/// Total number of tiles in the sandbox biome (20 × 20).
const int gardenPlotCount = 400;

/// Biome grid dimensions.
const int _gridSize = 20;

/// Full canvas size of the biome (a perfect square of square tiles).
const double _biomeSize = 800;

/// Half of the canvas — the size of a single seasonal quadrant.
const double _quadrantSize = _biomeSize / 2;

/// Growth stages: Stage 1 (0–24h) seedling, Stage 2 (1–3d) sapling,
/// Stage 3 (3d+) mature tree.
const Duration _stage1Threshold = Duration(days: 1);
const Duration _stage2Threshold = Duration(days: 3);

/// Seasonal tint applied to the Stage-1 seedling and Stage-2 sapling
/// silhouettes (which ship as flat white PNGs). Keyed by lowercase `seedType`.
const Map<String, Color> _seedSeasonalColors = {
  'birch': Color(0xFFF48FB1), // Spring — Soft Pink
  'oak': Color(0xFF81C784), // Summer — Vibrant Green
  'maple': Color(0xFFFF8A65), // Autumn — Burnt Orange
  'pine': Color(0xFF4FC3F7), // Winter — Ice Blue
};

/// Resolves the seasonal tint for a `seedType`, falling back to green.
Color _seasonalColorFor(String seedType) =>
    _seedSeasonalColors[seedType] ?? Colors.green;

/// Base ground color for each of the 4 seasonal quadrants.
///
/// Top-Left Spring, Top-Right Summer, Bottom-Left Autumn, Bottom-Right Winter.
Color _groundColorFor(int x, int y) {
  if (x < 10 && y < 10) return const Color(0xFFAED581); // Spring
  if (x >= 10 && y < 10) return const Color(0xFF66BB6A); // Summer
  if (x < 10 && y >= 10) return const Color(0xFFD84315); // Autumn
  return const Color(0xFFE0F7FA); // Winter
}

/// Cobblestone/dirt color for the demarcation cross.
const Color _pathColor = Color(0xFF795548);

/// True for the cobblestone path tiles that divide the 4 quadrants. Planting
/// is disabled on these specific indices.
bool _isPathTile(int x, int y) => x == 9 || x == 10 || y == 9 || y == 10;

// ---------------------------------------------------------------------------
// GardenTab — immersive zoomable 20×20 four-season sandbox biome
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
          width: _biomeSize,
          height: _biomeSize,
          child: Stack(
            children: [
              // ── 20×20 biome grid ────────────────────────────────────────
              Positioned.fill(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridSize,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: gardenPlotCount,
                  itemBuilder: (context, index) =>
                      _BiomeTile(index: index, garden: user.garden),
                ),
              ),

              // ── Winter: falling snow over the bottom-right quadrant ──────
              Positioned(
                left: _quadrantSize,
                top: _quadrantSize,
                width: _quadrantSize,
                height: _quadrantSize,
                child: IgnorePointer(
                  child: ClipRect(
                    child: SnowWidget(
                      snowConfig: const SnowConfig(
                        count: 30,
                        size: 16,
                        areaXStart: 0,
                        areaXEnd: _quadrantSize - 24,
                        areaYStart: 0,
                        areaYEnd: _quadrantSize - 24,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Spring: drifting petals/leaves over the top-left quadrant ─
              Positioned(
                left: 0,
                top: 0,
                width: _quadrantSize,
                height: _quadrantSize,
                child: IgnorePointer(
                  child: ClipRect(
                    child: WindWidget(
                      windConfig: const WindConfig(
                        color: Color(0xFFF48FB1),
                        width: 5,
                        y: _quadrantSize / 2,
                        windGap: 18,
                        slideXEnd: _quadrantSize - 20,
                      ),
                    ),
                  ),
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
// Single biome tile — base ground color + optional planted growth
// ---------------------------------------------------------------------------

class _BiomeTile extends ConsumerWidget {
  const _BiomeTile({required this.index, required this.garden});

  final int index;
  final List<GardenPlotModel> garden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final x = index % _gridSize;
    final y = index ~/ _gridSize;

    final onPath = _isPathTile(x, y);
    final plot = _plotForIndex(garden, index);
    final groundColor = onPath ? _pathColor : _groundColorFor(x, y);

    return GestureDetector(
      onTap: plot == null && !onPath
          ? () => _showSeedPicker(context, ref)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: groundColor,
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: plot == null
            ? _EmptyPlot(showHint: !onPath)
            : Center(child: _growthWidget(plot)),
      ),
    );
  }

  /// Renders the correct 3-stage growth visual for a planted plot:
  /// - Stage 1 (0–24h):   white seedling PNG tinted with the seasonal color
  /// - Stage 2 (1–3 days): white sapling PNG tinted with the seasonal color
  /// - Stage 3 (3+ days):  the mature seasonal tree for this `seedType`,
  ///   drawn full-color from `assets/images/<seedType>.png`.
  Widget _growthWidget(GardenPlotModel plot) {
    final age = DateTime.now().difference(plot.plantedAt);
    final seasonalColor = _seasonalColorFor(plot.seedType);
    if (age < _stage1Threshold) {
      return Image.asset(
        'assets/images/seedling.png',
        color: seasonalColor,
        fit: BoxFit.contain,
      );
    }
    if (age < _stage2Threshold) {
      return Image.asset(
        'assets/images/sapling.png',
        color: seasonalColor,
        fit: BoxFit.contain,
      );
    }
    return Image.asset(
      'assets/images/${plot.seedType}.png',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  void _showSeedPicker(BuildContext context, WidgetRef ref) {
    final coins = ref.read(rewardsProvider).coins;
    final cs = Theme.of(context).colorScheme;

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
                  'Seed Shop',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Plant a seasonal tree seed.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              for (final entry in seedCatalog) ...[
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.seasonEmoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  title: Text(
                    entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(entry.season),
                  trailing: Text(
                    '${entry.cost} ✨',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: coins >= entry.cost ? cs.primary : cs.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final ok = await ref
                        .read(rewardsProvider.notifier)
                        .plantSeed(index, entry.type);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? '${entry.name} planted! 🌱'
                              : 'Not enough ✨ to buy that seed.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
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
// Empty ground tile (subtle planting hint)
// ---------------------------------------------------------------------------

class _EmptyPlot extends StatelessWidget {
  const _EmptyPlot({required this.showHint});

  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: showHint
          ? Icon(
              Icons.add,
              size: 16,
              color: Colors.white.withValues(alpha: 0.40),
            )
          : null,
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
