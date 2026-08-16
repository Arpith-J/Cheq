// lib/screens/bundles_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rewards_provider.dart';
import '../theme/app_themes.dart';
import '../widgets/coin_pill.dart';
import 'theme_preview_screen.dart';

// ---------------------------------------------------------------------------
// BundlesScreen — Premium theme bundle shop
// ---------------------------------------------------------------------------

class BundlesScreen extends ConsumerStatefulWidget {
  const BundlesScreen({super.key});

  @override
  ConsumerState<BundlesScreen> createState() => _BundlesScreenState();
}

class _BundlesScreenState extends ConsumerState<BundlesScreen> {
  String? _busyThemeId;

  void _openPreview(ThemeCatalogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThemePreviewScreen(entry: entry)),
    );
  }

  Future<void> _equipTheme(ThemeCatalogEntry entry) async {
    setState(() => _busyThemeId = entry.id);

    final ok =
        await ref.read(rewardsProvider.notifier).equipTheme(entry.id);

    if (!mounted) return;
    setState(() => _busyThemeId = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${entry.name} is now your active theme!'
            : 'Could not equip ${entry.name}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userAsync = ref.watch(userStreamProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: cs.shadow.withValues(alpha: 0.08),
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 4,
        title: const Text(
          'Bundles',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          const CoinPill(),
          const SizedBox(width: 16),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => _BundlesGrid(
          unlockedThemes: user.unlockedThemes,
          activeTheme: user.activeTheme,
          coins: user.coins,
          busyThemeId: _busyThemeId,
          onPreview: _openPreview,
          onEquip: _equipTheme,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bundles Grid
// ---------------------------------------------------------------------------

class _BundlesGrid extends StatelessWidget {
  const _BundlesGrid({
    required this.unlockedThemes,
    required this.activeTheme,
    required this.coins,
    required this.busyThemeId,
    required this.onPreview,
    required this.onEquip,
  });

  final List<String> unlockedThemes;
  final String activeTheme;
  final int coins;
  final String? busyThemeId;
  final void Function(ThemeCatalogEntry entry) onPreview;
  final void Function(ThemeCatalogEntry entry) onEquip;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: appThemeCatalog.length,
      itemBuilder: (ctx, i) {
        final entry = appThemeCatalog[i];
        final isUnlocked = unlockedThemes.contains(entry.id);
        final isActive = activeTheme == entry.id;
        final canAfford = coins >= entry.cost;
        final isBusy = busyThemeId == entry.id;

        return _ShopCard(
          name: entry.name,
          description: entry.description,
          cost: entry.cost,
          icon: entry.icon,
          previewBackground: entry.previewBackground,
          previewAccent: entry.previewAccent,
          isUnlocked: isUnlocked,
          isActive: isActive,
          canAfford: canAfford,
          isBusy: isBusy,
          onPreview: () => onPreview(entry),
          onEquip: () => onEquip(entry),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Theme Shop Card
// ---------------------------------------------------------------------------

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.previewBackground,
    required this.previewAccent,
    required this.isUnlocked,
    required this.isActive,
    required this.canAfford,
    required this.isBusy,
    required this.onPreview,
    required this.onEquip,
  });

  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final Color previewBackground;
  final Color previewAccent;
  final bool isUnlocked;
  final bool isActive;
  final bool canAfford;
  final bool isBusy;
  final VoidCallback onPreview;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? cs.primary.withValues(alpha: 0.8)
              : cs.outlineVariant.withValues(alpha: 0.4),
          width: isActive ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Preview swatch ────────────────────────────────────────────
            Expanded(
              child: Container(
                color: previewBackground,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        icon,
                        size: 42,
                        color: previewAccent,
                      ),
                    ),
                    if (isActive)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.55),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildAction(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isActive) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded, size: 16),
        label: const Text('Equipped'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(36),
        ),
      );
    }

    // The free 'default' item is always owned and can never be purchased, so
    // it is treated purely as an equip/equipped target — never "Buy for 0".
    if (isUnlocked || cost <= 0) {
      return FilledButton.icon(
        onPressed: isBusy ? null : onEquip,
        icon: const Icon(Icons.palette_outlined, size: 16),
        label: Text(isBusy ? 'Equipping…' : 'Equip'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(36),
        ),
      );
    }

    final canAfford = this.canAfford;
    return FilledButton.icon(
      onPressed: isBusy ? null : onPreview,
      icon: Icon(
        canAfford ? Icons.visibility_outlined : Icons.lock_outline,
        size: 16,
      ),
      label: Text(isBusy ? 'Previewing…' : 'Preview'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(36),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        disabledBackgroundColor: cs.surfaceContainerHighest,
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
      ),
    );
  }
}
