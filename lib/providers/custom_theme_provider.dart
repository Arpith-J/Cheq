// lib/providers/custom_theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 🌟 Default colors list for the user settings picker choices
const List<Color> appAccentSwatches = [
  Color(0xff4caf50), // 0. Default Cheq Green
  Color(0xFF2196F3), // 1. Electric Blue
  Color(0xFF9C27B0), // 2. Vivid Purple
  Color(0xFFFF9800), // 3. Energetic Orange
  Color(0xFFE91E63), // 4. Rose Pink
  Color(0xFF96F3E1),
];

final customAccentProvider = NotifierProvider<CustomAccentNotifier, Color>(
  CustomAccentNotifier.new,
);

class CustomAccentNotifier extends Notifier<Color> {
  @override
  Color build() {
    return appAccentSwatches.first; // Defaults smoothly to the green color
  }

  void updateAccentColor(Color newColor) {
    state = newColor;
  }
}