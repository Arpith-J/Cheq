// lib/screens/constellation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/star_model.dart';
import '../models/user_model.dart';
import '../providers/rewards_provider.dart';
import '../widgets/coin_pill.dart';
import '../widgets/constellation_painter.dart';

/// Full-screen immersive mode for the Constellation Data Core. The background
/// adapts to the active theme — deep black on dark themes, the themed surface
/// color on light themes (e.g. Soft Paper) — so the close button, lines, and
/// icons always stay visible.
class ConstellationScreen extends ConsumerStatefulWidget {
  const ConstellationScreen({super.key});

  @override
  ConsumerState<ConstellationScreen> createState() =>
      _ConstellationScreenState();
}

class _ConstellationScreenState extends ConsumerState<ConstellationScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the sparkle/twinkle animation. Loops forever until paused.
  late final AnimationController _controller;

  /// When true, the sparkle animation is frozen so stars can be rearranged.
  bool _isPaused = false;

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
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ConstellationView(
                animation: _controller,
                paused: _isPaused,
              ),
            ),
            // ── Exit full-screen mode (top-left) ───────────────────────────
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close, color: foreground),
                style: IconButton.styleFrom(
                  backgroundColor: buttonBackground,
                  foregroundColor: foreground,
                ),
              ),
            ),
            // ── Live coin balance (top-right) ──────────────────────────────
            Positioned(
              top: 8,
              right: 8,
              child: const CoinPill(),
            ),
            // ── Pause / Play rotation toggle (below the coin balance) ──────
            Positioned(
              top: 64,
              right: 8,
              child: IconButton(
                onPressed: _togglePause,
                icon: Icon(
                  _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: foreground,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: buttonBackground,
                  foregroundColor: foreground,
                ),
                tooltip: _isPaused ? 'Play' : 'Pause',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reusable heart of the Constellation feature: the animated CustomPaint
/// star field with pan/drag interaction, an empty-state hint, and the
/// glassmorphism "buy star" panel.
class ConstellationView extends ConsumerStatefulWidget {
  const ConstellationView({
    super.key,
    required this.animation,
    required this.paused,
  });

  /// Drives the sparkle/twinkle animation (owned by the host screen so the
  /// full-screen pause toggle can stop/repeat it).
  final AnimationController animation;

  /// When true, the sparkle animation is frozen so stars can be rearranged.
  final bool paused;

  @override
  ConsumerState<ConstellationView> createState() =>
      _ConstellationViewState();
}

class _ConstellationViewState extends ConsumerState<ConstellationView> {
  bool _isBuying = false;
  bool _panelExpanded = false;

  /// The star currently being dragged (only meaningful while paused).
  String? _draggedStarId;

  /// Returns the star whose canvas position is within ~30px of [pos], or null.
  /// Delegates to the painter so hit tests match what is actually rendered
  /// (drift animation included).
  StarModel? _starAt(Offset pos, Size size) {
    return ConstellationPainter.starAt(
      ref.read(rewardsProvider).constellation,
      size,
      pos,
      animationValue: widget.animation.value,
    );
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (!widget.paused) return;
    // Only claim the gesture when the touch actually lands on a star;
    // otherwise ignore it so the InteractiveViewer can pan/zoom.
    final star = _starAt(details.localPosition, size);
    if (star == null) return;
    setState(() => _draggedStarId = star.id);
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final draggedId = _draggedStarId;
    if (draggedId == null) return;
    // Reposition the held star to the finger, clamped to the canvas so it
    // can never be dragged off-screen.
    final dx =
        (details.localPosition.dx / size.width).clamp(0.05, 0.95).toDouble();
    final dy =
        (details.localPosition.dy / size.height).clamp(0.05, 0.95).toDouble();
    ref.read(rewardsProvider.notifier).previewStarMove(draggedId, dx, dy);
  }

  void _handlePanEnd(DragEndDetails details) {
    final draggedId = _draggedStarId;
    setState(() => _draggedStarId = null);

    if (draggedId == null) return;

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
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: GestureDetector(
                    // Only claim touches that land on a star (the painter's
                    // hitTest only hits near rendered stars); everything else
                    // falls through to the InteractiveViewer for pan/zoom.
                    behavior: HitTestBehavior.deferToChild,
                    onPanStart: widget.paused
                        ? (details) => _handlePanStart(details, canvasSize)
                        : null,
                    onPanUpdate: widget.paused
                        ? (details) => _handlePanUpdate(details, canvasSize)
                        : null,
                    onPanEnd: widget.paused ? _handlePanEnd : null,
                    child: AnimatedBuilder(
                      animation: widget.animation,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: ConstellationPainter(
                          stars: user.constellation,
                          animationValue: widget.animation.value,
                          canvasSize: canvasSize,
                          lineColor: lineColor,
                        ),
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
