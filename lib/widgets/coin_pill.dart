// lib/widgets/coin_pill.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/coins_provider.dart';

/// Always-visible coin balance pill (sparkle + formatted count). It pulses
/// briefly whenever the live coin balance changes. Shared across the main
/// AppBar, the Bundles AppBar and the Constellation full-screen chrome.
class CoinPill extends ConsumerStatefulWidget {
  const CoinPill({super.key});

  @override
  ConsumerState<CoinPill> createState() => _CoinPillState();
}

class _CoinPillState extends ConsumerState<CoinPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ).drive(Tween<double>(begin: 0.75, end: 1.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(coinsProvider).value ?? 0;

    ref.listen<AsyncValue<int>>(coinsProvider, (previous, next) {
      final prev = previous?.value;
      final curr = next.value;
      if (prev == null || curr == null || curr == prev) return;
      _controller.forward(from: 0);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    const gold = Color(0xFFFFD54F);
    final onGold = isDark ? const Color(0xFFB8860B) : const Color(0xFF6D4C00);

    return ScaleTransition(
      scale: _scale,
      child: Container(
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
            Text('✨', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              _format(coins),
              key: ValueKey<int>(coins),
              style: TextStyle(
                color: onGold,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Standard comma-separated number formatting, e.g. 9500 -> '9,500'.
  String _format(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
}
