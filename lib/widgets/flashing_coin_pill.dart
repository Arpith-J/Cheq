// lib/widgets/flashing_coin_pill.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/coins_provider.dart';
import 'coin_pill.dart';

/// Coin balance pill that stays HIDDEN by default and only flashes into view
/// for a brief 2-second window whenever the live coin balance increases.
///
/// Used on the main tabs (ToDo / Planner / Spaces), where the economy should
/// stay out of sight until it is actually earned. The permanently visible
/// [CoinPill] remains the widget of choice for the Bundles and Constellation
/// screens.
class FlashingCoinPill extends ConsumerStatefulWidget {
  const FlashingCoinPill({super.key});

  @override
  ConsumerState<FlashingCoinPill> createState() => _FlashingCoinPillState();
}

class _FlashingCoinPillState extends ConsumerState<FlashingCoinPill> {
  /// Fully hidden by default; flipped to 1.0 while flashing.
  double _opacity = 0.0;

  /// Armed on every earning; fires 2 seconds later to hide the pill again.
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<int>>(coinsProvider, (previous, next) {
      final prev = previous?.value;
      final curr = next.value;
      // Only an actual increase earns a flash; drops/unchanged stay hidden.
      if (prev == null || curr == null || curr <= prev) return;

      // Balance went up: pop the pill in and re-arm the hide timer so a second
      // earning landing inside the 2-second window keeps it visible instead of
      // blinking out mid-earn.
      _hideTimer?.cancel();
      setState(() => _opacity = 1.0);
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _opacity = 0.0);
      });
    });

    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      // Reuses the standard coin pill UI; the outer AnimatedOpacity alone
      // controls its visibility on the main tabs.
      child: const CoinPill(),
    );
  }
}
