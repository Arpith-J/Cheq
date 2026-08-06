// lib/theme/app_themes.dart

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Theme IDs
// ---------------------------------------------------------------------------

const String themeIdDefault = 'default';
const String themeIdOledMidnight = 'oledMidnight';
const String themeIdCyberpunk = 'cyberpunk';
const String themeIdSoftPaper = 'softPaper';

const String appName = String.fromEnvironment('APP_NAME', defaultValue: 'Cheq');

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

/// Pure #000000 OLED bundle. Deep, power-saving blacks on every surface with
/// very dark grey cards and sharp, almost-square corners. Dark-only.
final ThemeData oledMidnightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF000000),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF66BB6A),
    brightness: Brightness.dark,
    primary: const Color(0xFF66BB6A),
    secondary: const Color(0xFF80CBC4),
    surface: const Color(0xFF000000),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0D0D0D),
    surfaceContainer: const Color(0xFF131313),
    surfaceContainerHigh: const Color(0xFF1A1A1A),
    surfaceContainerHighest: const Color(0xFF232323),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF000000),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  cardTheme: const CardThemeData(
    color: Color(0xFF131313),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
  ),
);

/// Dark synthwave bundle. Deep navy/purple backdrop with high-contrast neon
/// magenta and cyan accents. Dark-only by design.
final ThemeData cyberpunkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0D0B1E),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF2E88),
    brightness: Brightness.dark,
    primary: const Color(0xFFFF2E88),
    secondary: const Color(0xFF00F0FF),
    tertiary: const Color(0xFFAA44FF),
    surface: const Color(0xFF131126),
    surfaceContainerLowest: const Color(0xFF0D0B1E),
    surfaceContainerLow: const Color(0xFF191632),
    surfaceContainer: const Color(0xFF1F1B3B),
    surfaceContainerHigh: const Color(0xFF282250),
    surfaceContainerHighest: const Color(0xFF332B66),
    error: const Color(0xFFFF5C8A),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0D0B1E),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  cardTheme: const CardThemeData(
    color: Color(0xFF1F1B3B),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: Color(0x2E00F0FF)),
    ),
  ),
);

/// Warm, tactile, light bundle. Cream/off-white pages, completely flat UI
/// (zero elevation) and heavily rounded, pillowy cards. Light-only by design.
final ThemeData softPaperTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFF4F0EB),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFA98467),
    brightness: Brightness.light,
    primary: const Color(0xFF9A7B5F),
    secondary: const Color(0xFF7BA38B),
    tertiary: const Color(0xFFB8A27A),
    surface: const Color(0xFFFDFBF7),
    surfaceContainerLowest: const Color(0xFFF4F0EB),
    surfaceContainerLow: const Color(0xFFF0EAE2),
    surfaceContainer: const Color(0xFFEBE3D8),
    surfaceContainerHigh: const Color(0xFFE4D9CB),
    surfaceContainerHighest: const Color(0xFFDCCFC0),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF4F0EB),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  cardTheme: const CardThemeData(
    color: Color(0xFFFFFFFF),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    ),
  ),
);

/// The fixed premium bundles. The "default" theme is dynamic (accent-based)
/// and therefore resolved separately in [buildDefaultTheme].
final Map<String, ThemeData> appThemes = {
  themeIdOledMidnight: oledMidnightTheme,
  themeIdCyberpunk: cyberpunkTheme,
  themeIdSoftPaper: softPaperTheme,
};

// ---------------------------------------------------------------------------
// Shop catalog
// ---------------------------------------------------------------------------

class ThemeCatalogEntry {
  final String id;
  final String name;
  final String description;
  final String colorDescription;
  final int cost;
  final IconData icon;
  final Color previewBackground;
  final Color previewAccent;

  const ThemeCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.colorDescription,
    required this.cost,
    required this.icon,
    required this.previewBackground,
    required this.previewAccent,
  });
}

const ThemeCatalogEntry defaultThemeEntry = ThemeCatalogEntry(
  id: themeIdDefault,
  name: 'Default',
  description: 'The classic $appName look, tuned to your accent color.',
  colorDescription:
      'Clean Neutral Surfaces with Your Chosen Accent Highlights',
  cost: 0,
  icon: Icons.palette_outlined,
  previewBackground: Color(0xFFFAFAFA),
  previewAccent: Color(0xFF4caf50),
);

const ThemeCatalogEntry oledMidnightThemeEntry = ThemeCatalogEntry(
  id: themeIdOledMidnight,
  name: 'OLED Midnight',
  description:
      'Pure black screens and sharp, minimalist cards for deep power-saving blacks.',
  colorDescription: 'Pure Black Background with Mint Green Accents',
  cost: 500,
  icon: Icons.dark_mode_outlined,
  previewBackground: Color(0xFF000000),
  previewAccent: Color(0xFF66BB6A),
);

const ThemeCatalogEntry cyberpunkThemeEntry = ThemeCatalogEntry(
  id: themeIdCyberpunk,
  name: 'Cyberpunk',
  description:
      'Neon magenta and cyan slicing through a dark synthwave night.',
  colorDescription: 'Deep Navy Background with Neon Magenta & Cyan Accents',
  cost: 1000,
  icon: Icons.electric_bolt_outlined,
  previewBackground: Color(0xFF0D0B1E),
  previewAccent: Color(0xFFFF2E88),
);

const ThemeCatalogEntry softPaperThemeEntry = ThemeCatalogEntry(
  id: themeIdSoftPaper,
  name: 'Soft Paper',
  description:
      'Warm cream pages with flat, pillowy rounded cards for a calm, tactile feel.',
  colorDescription: 'Warm Cream Paper with Soft Shadows',
  cost: 1000,
  icon: Icons.wb_sunny_outlined,
  previewBackground: Color(0xFFF4F0EB),
  previewAccent: Color(0xFF9A7B5F),
);

const List<ThemeCatalogEntry> appThemeCatalog = [
  defaultThemeEntry,
  oledMidnightThemeEntry,
  cyberpunkThemeEntry,
  softPaperThemeEntry,
];

ThemeCatalogEntry? themeEntryById(String id) {
  for (final entry in appThemeCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}
