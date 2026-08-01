// lib/screens/constellation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/rewards_provider.dart';
import '../widgets/constellation_painter.dart';

/// Full-screen immersive mode for the Constellation Data Core. Uses a deep
/// black scaffold with a safe-area close button; the interactive star field
/// and purchase panel live in the shared [ConstellationView].
class ConstellationScreen extends StatelessWidget {
  const ConstellationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    foregroundColor: Colors.white,
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

    return userAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) => Stack(
        children: [
          // ── Interactive star field ─────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() => _panOffset += details.delta);
              },
              onPanEnd: (_) => setState(() => _panOffset = Offset.zero),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: ConstellationPainter(
                    stars: user.constellation,
                    animationValue: _controller.value,
                    panOffset: _panOffset,
                  ),
                ),
              ),
            ),
          ),
          if (user.constellation.isEmpty)
            const Center(
              child: Text(
                'Your constellation is empty.\nBuy a star below to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          // ── Full screen affordance ─────────────────────────────────────
          if (widget.onFullScreen != null)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: widget.onFullScreen,
                icon: const Icon(Icons.fullscreen, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                ),
                tooltip: 'Full screen',
              ),
            ),
          // ── Glassmorphism purchase panel ───────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 28,
            child: _BuildPanel(
              user: user,
              isBuying: _isBuying,
              onBuyStar: _buyStar,
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
  });

  final UserModel user;
  final bool isBuying;
  final void Function(String category) onBuyStar;

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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coin balance
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.monetization_on_rounded,
                color: Color(0xFFFFD54F),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '${user.coins}',
                style: const TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final entry in starCosts.entries)
                _StarBuyButton(
                  label: '${_labelFor(entry.key)}: ${entry.value}',
                  canAfford: user.coins >= entry.value,
                  isBusy: isBuying,
                  onPressed: () => onBuyStar(entry.key),
                ),
            ],
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
    final enabled = canAfford && !isBusy;
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(
        canAfford ? Icons.star_rounded : Icons.lock_outline,
        size: 16,
      ),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
      ),
    );
  }
}
