// lib/widgets/coin_flash_overlay.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rewards_provider.dart';

/// Transient "+N Coins" pill shown in the top-right corner of the main
/// scaffold. It listens to the live user document and pops in whenever the coin
/// balance grows, stays visible for 2 seconds, then fades out completely.
class CoinFlashOverlay extends ConsumerStatefulWidget {
  const CoinFlashOverlay({super.key});

  @override
  ConsumerState<CoinFlashOverlay> createState() => _CoinFlashOverlayState();
}

class _CoinFlashOverlayState extends ConsumerState<CoinFlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  Timer? _hideTimer;
  int _flashAmount = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 0,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _flash(int delta) {
    if (!mounted) return;
    setState(() => _flashAmount = delta);
    _hideTimer?.cancel();
    _fadeCtrl.forward(from: 0);
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _fadeCtrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userStreamProvider, (previous, next) {
      final prevCoins = previous?.value?.coins;
      final nextCoins = next.value?.coins;
      if (prevCoins == null || nextCoins == null) return;
      if (nextCoins > prevCoins) _flash(nextCoins - prevCoins);
    });

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _fadeCtrl,
        builder: (context, _) {
          final opacity = _fadeCtrl.value;
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, (1 - opacity) * -8),
              child: _CoinFlashPill(amount: _flashAmount),
            ),
          );
        },
      ),
    );
  }
}

class _CoinFlashPill extends StatelessWidget {
  const _CoinFlashPill({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const gold = Color(0xFFFFD54F);
    final onGold = isDark ? const Color(0xFFB8860B) : const Color(0xFF6D4C00);

    return Container(
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
          Icon(Icons.monetization_on_rounded, size: 16, color: gold),
          const SizedBox(width: 6),
          Text(
            '+$amount Coins',
            style: TextStyle(
              color: onGold,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
