import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The Riverpod 3.x compliant theme notifier
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light; // Baseline starting theme

  void toggleTheme() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }
}