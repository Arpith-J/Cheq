// lib/theme/app_themes.dart

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Theme IDs
// ---------------------------------------------------------------------------

const String themeIdDefault = 'default';
const String themeIdOledBlack = 'oledBlack';
const String themeIdCyberpunk = 'cyberpunk';
const String themeIdPastel = 'pastel';

// ---------------------------------------------------------------------------
// Theme definitions
// ---------------------------------------------------------------------------

/// Builds the stock "Default" theme. Seed-based so it keeps honoring the
/// user's custom accent color and the light/dark mode toggle in Settings.
ThemeData buildDefaultTheme({
  required Color accent,
  required Brightness brightness,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ),
  );
}

/// Pure #000000 OLED theme. Dark-only by design.
final ThemeData oledBlackTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF000000),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4caf50),
    brightness: Brightness.dark,
    primary: const Color(0xFF66BB6A),
    secondary: const Color(0xFF80CBC4),
    surface: const Color(0xFF000000),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0E0E0E),
    surfaceContainer: const Color(0xFF141414),
    surfaceContainerHigh: const Color(0xFF1B1B1B),
    surfaceContainerHighest: const Color(0xFF242424),
  ),
);

/// Dark cyberpunk theme with neon pink + cyan accents. Dark-only by design.
final ThemeData cyberpunkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0A0A14),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF2E88),
    brightness: Brightness.dark,
    primary: const Color(0xFFFF2E88),
    secondary: const Color(0xFF00F0FF),
    tertiary: const Color(0xFFAA44FF),
    surface: const Color(0xFF131320),
    surfaceContainerLowest: const Color(0xFF0A0A14),
    surfaceContainerLow: const Color(0xFF171725),
    surfaceContainer: const Color(0xFF1D1D2E),
    surfaceContainerHigh: const Color(0xFF252538),
    surfaceContainerHighest: const Color(0xFF2E2E45),
    error: const Color(0xFFFF5C8A),
  ),
);

/// Soft, warm, light minimalist theme. Light-only by design.
final ThemeData pastelTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFFFF7EE),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFF4A6C0),
    brightness: Brightness.light,
    primary: const Color(0xFFE88CA8),
    secondary: const Color(0xFF9DD8C6),
    tertiary: const Color(0xFFB9A7E0),
    surface: const Color(0xFFFFFDF8),
    surfaceContainerLowest: const Color(0xFFFFF7EE),
    surfaceContainerLow: const Color(0xFFFDF1E4),
    surfaceContainer: const Color(0xFFF9EAD9),
    surfaceContainerHigh: const Color(0xFFF5E1CC),
    surfaceContainerHighest: const Color(0xFFEFD7BD),
  ),
);

/// The three fixed palettes. The "default" theme is dynamic (accent-based)
/// and therefore resolved separately in [buildDefaultTheme].
final Map<String, ThemeData> appThemes = {
  themeIdOledBlack: oledBlackTheme,
  themeIdCyberpunk: cyberpunkTheme,
  themeIdPastel: pastelTheme,
};

// ---------------------------------------------------------------------------
// Shop catalog
// ---------------------------------------------------------------------------

class ThemeCatalogEntry {
  final String id;
  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final Color previewBackground;
  final Color previewAccent;

  const ThemeCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.previewBackground,
    required this.previewAccent,
  });
}

const ThemeCatalogEntry defaultThemeEntry = ThemeCatalogEntry(
  id: themeIdDefault,
  name: 'Default',
  description: 'The classic Cheq look, tuned to your accent color.',
  cost: 0,
  icon: Icons.palette_outlined,
  previewBackground: Color(0xFFFAFAFA),
  previewAccent: Color(0xFF4caf50),
);

const ThemeCatalogEntry oledBlackThemeEntry = ThemeCatalogEntry(
  id: themeIdOledBlack,
  name: 'OLED Black',
  description: 'Pure #000000 backgrounds for deep, power-saving blacks.',
  cost: 500,
  icon: Icons.dark_mode_outlined,
  previewBackground: Color(0xFF000000),
  previewAccent: Color(0xFF66BB6A),
);

const ThemeCatalogEntry cyberpunkThemeEntry = ThemeCatalogEntry(
  id: themeIdCyberpunk,
  name: 'Cyberpunk',
  description: 'Neon pink and cyan accents against a dark synthwave night.',
  cost: 1000,
  icon: Icons.electric_bolt_outlined,
  previewBackground: Color(0xFF0A0A14),
  previewAccent: Color(0xFFFF2E88),
);

const ThemeCatalogEntry pastelThemeEntry = ThemeCatalogEntry(
  id: themeIdPastel,
  name: 'Pastel',
  description: 'Soft, warm, light minimalist colors for an easy on the eyes day.',
  cost: 750,
  icon: Icons.wb_sunny_outlined,
  previewBackground: Color(0xFFFFF7EE),
  previewAccent: Color(0xFFE88CA8),
);

const List<ThemeCatalogEntry> appThemeCatalog = [
  defaultThemeEntry,
  oledBlackThemeEntry,
  cyberpunkThemeEntry,
  pastelThemeEntry,
];

ThemeCatalogEntry? themeEntryById(String id) {
  for (final entry in appThemeCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}
