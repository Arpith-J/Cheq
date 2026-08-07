// lib/screens/constellation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/star_model.dart';
import '../models/user_model.dart';
import '../providers/rewards_provider.dart';
import '../widgets/constellation_painter.dart';

/// Full-screen immersive mode for the Constellation Data Core. The background
/// adapts to the active theme — deep black on dark themes, the themed surface
/// color on light themes (e.g. Soft Paper) — so the close button, lines, and
/// icons always stay visible.
class ConstellationScreen extends StatelessWidget {
  const ConstellationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final foreground = isDark ? Colors.white : cs.onSurface;
    final buttonBackground = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : cs.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: ConstellationView()),
          // ── Exit full-screen mode ───────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, color: foreground),
                  style: IconButton.styleFrom(
                    backgroundColor: buttonBackground,
                    foregroundColor: foreground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reusable heart of the Constellation feature: the animated CustomPaint
/// star field with pan/drag interaction, an empty-state hint, and the
/// glassmorphism "buy star" panel. When [onFullScreen] is provided, a floating
/// full-screen button is rendered in the top-right corner.
class ConstellationView extends ConsumerStatefulWidget {
  const ConstellationView({super.key, this.onFullScreen});

  final VoidCallback? onFullScreen;

  @override
  ConsumerState<ConstellationView> createState() =>
      _ConstellationViewState();
}

class _ConstellationViewState extends ConsumerState<ConstellationView>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  Offset _panOffset = Offset.zero;
  bool _isBuying = false;
  bool _panelExpanded = false;

  /// When true, the sparkle animation is frozen so stars can be rearranged.
  bool _isPaused = false;

  /// The star currently being dragged (only meaningful while paused).
  String? _draggedStarId;

  @override
  void initState() {
    super.initState();
    // Loops forever to drive the sparkle/twinkle animation.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  /// Returns the star whose canvas position is within ~30px of [pos], or null.
  StarModel? _starAt(Offset pos, Size size) {
    final stars = ref.read(rewardsProvider).constellation;
    StarModel? nearest;
    var bestSquared = 30.0 * 30.0;
    for (final star in stars) {
      final sx = star.dx * size.width;
      final sy = star.dy * size.height;
      final dx = pos.dx - sx;
      final dy = pos.dy - sy;
      final distSquared = dx * dx + dy * dy;
      if (distSquared <= bestSquared) {
        bestSquared = distSquared;
        nearest = star;
      }
    }
    return nearest;
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (!_isPaused) return;
    setState(() {
      _draggedStarId = _starAt(details.localPosition, size)?.id;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final draggedId = _draggedStarId;
    if (draggedId != null) {
      // Reposition the held star to the finger, clamped to the canvas so it
      // can never be dragged off-screen.
      final dx =
          (details.localPosition.dx / size.width).clamp(0.05, 0.95).toDouble();
      final dy =
          (details.localPosition.dy / size.height).clamp(0.05, 0.95).toDouble();
      ref.read(rewardsProvider.notifier).previewStarMove(draggedId, dx, dy);
    } else {
      // No star grabbed — preserve the original pan-the-field behavior.
      setState(() => _panOffset += details.delta);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    final draggedId = _draggedStarId;
    setState(() => _draggedStarId = null);

    if (draggedId == null) {
      setState(() => _panOffset = Offset.zero);
      return;
    }

    // Persist the dragged star's final position to Firestore.
    final user = ref.read(rewardsProvider);
    final idx = user.constellation.indexWhere((s) => s.id == draggedId);
    if (idx >= 0) {
      final star = user.constellation[idx];
      ref.read(rewardsProvider.notifier).moveStar(star.id, star.dx, star.dy);
    }
  }

  Future<void> _buyStar(String category) async {
    setState(() => _isBuying = true);
    final ok = await ref.read(rewardsProvider.notifier).purchaseStar(category);
    if (!mounted) return;
    setState(() => _isBuying = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough coins for that star.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userStreamProvider);
    // Watch the NotifierProvider (not the raw stream) so optimistic star drags
    // repaint instantly; the stream is still watched for loading/error states.
    final user = ref.watch(rewardsProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final foreground = isDark ? Colors.white : cs.onSurface;
    final lineColor = isDark ? Colors.white : cs.onSurface;

    return userAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          color: cs.onSurface.withValues(alpha: 0.54),
        ),
      ),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: cs.error)),
      ),
      data: (_) => Stack(
        children: [
          // ── Interactive star field ─────────────────────────────────────
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _handlePanStart(details, canvasSize),
                  onPanUpdate: (details) =>
                      _handlePanUpdate(details, canvasSize),
                  onPanEnd: _handlePanEnd,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: ConstellationPainter(
                        stars: user.constellation,
                        animationValue: _controller.value,
                        panOffset: _panOffset,
                        lineColor: lineColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (user.constellation.isEmpty)
            Center(
              child: Text(
                'Your constellation is empty.\nBuy a star below to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.38),
                  fontSize: 14,
                ),
              ),
            ),
          // ── Compact balance pill (full-screen mode only) ───────────────
          // The embedded shop tab already shows its own balance chip in the
          // header, so only the immersive full-screen view gets a pill here.
          if (widget.onFullScreen == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: _BalancePill(coins: user.coins),
                ),
              ),
            ),
          // ── Full screen affordance ─────────────────────────────────────
          if (widget.onFullScreen != null)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: widget.onFullScreen,
                icon: Icon(Icons.fullscreen, color: foreground),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.06),
                  foregroundColor: foreground,
                ),
                tooltip: 'Full screen',
              ),
            ),
          // ── Play / Pause ───────────────────────────────────────────────
          Positioned(
            top: widget.onFullScreen != null ? 64 : 12,
            right: 12,
            child: IconButton(
              onPressed: _togglePause,
              icon: Icon(
                _isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: foreground,
              ),
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                foregroundColor: foreground,
              ),
              tooltip: _isPaused ? 'Play' : 'Pause',
            ),
          ),
          // ── Collapsible glassmorphism purchase panel ──────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Expanded glass panel
                AnimatedSlide(
                  offset: _panelExpanded
                      ? Offset.zero
                      : const Offset(0, 1.5),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedOpacity(
                    opacity: _panelExpanded ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: !_panelExpanded,
                      child: _BuildPanel(
                        user: user,
                        isBuying: _isBuying,
                        onBuyStar: _buyStar,
                        onCollapse: () =>
                            setState(() => _panelExpanded = false),
                      ),
                    ),
                  ),
                ),
                // Collapsed floating pill (default)
                AnimatedSlide(
                  offset: _panelExpanded
                      ? const Offset(0, 1.5)
                      : Offset.zero,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedOpacity(
                    opacity: _panelExpanded ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: _panelExpanded,
                      child: _BuyPill(
                        onTap: () => setState(() => _panelExpanded = true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glassmorphism purchase panel
// ---------------------------------------------------------------------------

class _BuildPanel extends StatelessWidget {
  const _BuildPanel({
    required this.user,
    required this.isBuying,
    required this.onBuyStar,
    required this.onCollapse,
  });

  final UserModel user;
  final bool isBuying;
  final void Function(String category) onBuyStar;
  final VoidCallback onCollapse;

  String _labelFor(String category) {
    switch (category) {
      case 'creativity':
        return 'Creativity';
      case 'academic':
        return 'Academic';
      default:
        return 'Focus';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final foreground = isDark ? Colors.white : cs.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : cs.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with collapse affordance
          Row(
            children: [
              Expanded(
                child: Text(
                  'Buy Stars',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onCollapse,
                tooltip: 'Collapse',
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: foreground,
                  size: 20,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : cs.surfaceContainerHighest,
                  foregroundColor: foreground,
                  padding: const EdgeInsets.all(4),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Horizontally scrollable star categories
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (final entry in starCosts.entries) ...[
                  _StarBuyButton(
                    label: '${_labelFor(entry.key)}: ${entry.value}',
                    canAfford: user.coins >= entry.value,
                    isBusy: isBuying,
                    onPressed: () => onBuyStar(entry.key),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarBuyButton extends StatelessWidget {
  const _StarBuyButton({
    required this.label,
    required this.canAfford,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final bool canAfford;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = canAfford && !isBusy;

    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(
        canAfford ? Icons.star_rounded : Icons.lock_outline,
        size: 16,
      ),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : cs.primaryContainer.withValues(alpha: 0.8),
        foregroundColor: isDark ? Colors.white : cs.onSurface,
        disabledBackgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : cs.surfaceContainerHighest,
        disabledForegroundColor: isDark
            ? Colors.white.withValues(alpha: 0.35)
            : cs.onSurface.withValues(alpha: 0.35),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsed "Buy Stars" pill
// ---------------------------------------------------------------------------

class _BuyPill extends StatelessWidget {
  const _BuyPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final foreground = isDark ? Colors.white : cs.onSurface;
    final background = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : cs.surfaceContainerHigh.withValues(alpha: 0.92);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, color: foreground, size: 18),
              const SizedBox(width: 8),
              Text(
                'Buy Stars',
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                color: foreground,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact balance pill
// ---------------------------------------------------------------------------

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final onGold = isDark ? const Color(0xFFB8860B) : const Color(0xFF6D4C00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : cs.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
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
            '$coins',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: onGold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
