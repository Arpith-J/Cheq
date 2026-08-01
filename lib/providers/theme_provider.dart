// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../main.dart'; // Import this to access sharedPrefsProvider
import '../theme/app_themes.dart';
import 'custom_theme_provider.dart';
import 'rewards_provider.dart';

// The Riverpod 3.x compliant theme notifier
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // 1. Instantly load the cached theme on boot (Zero network delay = zero flash!)
    final prefs = ref.watch(sharedPrefsProvider);
    final isDark = prefs.getBool('isDarkMode');
    
    if (isDark != null) {
      return isDark ? ThemeMode.dark : ThemeMode.light;
    }
    return ThemeMode.light; // Baseline starting theme
  }

  void toggleTheme() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    
    // 2. Save it locally immediately so it's ready for the next app launch
    ref.read(sharedPrefsProvider).setBool('isDarkMode', state == ThemeMode.dark);

    // 3. Keep your existing background sync to Firebase
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.saveUserSettings(uid, {
        'isDarkMode': state == ThemeMode.dark,
      });
    }
  }

  // 4. Update your load method to ensure cloud changes sync down to local storage
  Future<void> loadSettings(String uid) async {
    final settings = await FirestoreService.instance.getUserSettings(uid);
    if (settings != null && settings.containsKey('isDarkMode')) {
      final isDark = settings['isDarkMode'] as bool;
      state = isDark ? ThemeMode.dark : ThemeMode.light;
      
      // Sync cloud truth to local cache
      ref.read(sharedPrefsProvider).setBool('isDarkMode', isDark);
    }
  }
}

/// Light + dark [ThemeData] pair to feed into [MaterialApp].
class AppThemePair {
  final ThemeData light;
  final ThemeData dark;

  const AppThemePair({required this.light, required this.dark});
}

/// Resolves the app-wide theme from the user's `activeTheme`.
///
/// - `default`    → standard Light/Dark mode, honoring the free accent picker.
/// - `oledMidnight` / `cyberpunk` / `softPaper` → their fixed premium bundle.
/// - Unknown ids fall back to the default theme.
final appThemeProvider = Provider<AppThemePair>((ref) {
  final activeTheme = ref.watch(rewardsProvider).activeTheme;
  final accent = ref.watch(customAccentProvider);

  final bool isDefaultTheme = activeTheme == themeIdDefault;
  final ThemeData? fixedTheme = appThemes[activeTheme];

  final light = isDefaultTheme
      ? buildDefaultTheme(accent: accent, brightness: Brightness.light)
      : fixedTheme ??
          buildDefaultTheme(accent: accent, brightness: Brightness.light);
  final dark = isDefaultTheme
      ? buildDefaultTheme(accent: accent, brightness: Brightness.dark)
      : fixedTheme ??
          buildDefaultTheme(accent: accent, brightness: Brightness.dark);

  return AppThemePair(light: light, dark: dark);
});
