// lib/providers/coins_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoinsNotifier extends Notifier<int> {
  static const int _maxCoins = 999999;
  static const int _minCoins = 0;

  @override
  int build() => 0; // Initial coin balance

  /// Adds [amount] coins. Clamps at [_maxCoins]. Returns the delta actually added.
  int increment(int amount) {
    assert(amount > 0, 'Increment amount must be positive.');
    final before = state;
    state = (state + amount).clamp(_minCoins, _maxCoins);
    return state - before;
  }

  /// Deducts [amount] coins. Returns `false` if the balance is insufficient.
  bool decrement(int amount) {
    assert(amount > 0, 'Decrement amount must be positive.');
    if (state < amount) return false;
    state = (state - amount).clamp(_minCoins, _maxCoins);
    return true;
  }

  /// Hard-resets the balance. Useful when loading a fresh user session.
  void reset(int coins) {
    assert(coins >= _minCoins, 'Coins cannot be negative.');
    state = coins.clamp(_minCoins, _maxCoins);
  }
}

final coinsProvider = NotifierProvider<CoinsNotifier, int>(
  CoinsNotifier.new,
);