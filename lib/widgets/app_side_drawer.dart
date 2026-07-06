// lib/widgets/app_side_drawer.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../providers/theme_provider.dart';
import '../providers/custom_theme_provider.dart';
import '../screens/main_scaffold.dart'; // To access the ProfileAvatar widget

class AppSideDrawer extends ConsumerWidget {
  const AppSideDrawer({super.key});

  // The Custom Color Picker Dialog
  void _showColorPickerDialog(BuildContext context, WidgetRef ref, Color currentColor) {
    Color pickerColor = currentColor;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Pick a custom theme color!'),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: pickerColor,
                  onColorChanged: (Color color) {
                    setStateInDialog(() {
                      pickerColor = color;
                    });
                  },
                  pickerAreaHeightPercent: 0.8,
                  enableAlpha: false,
                  displayThumbColor: true,
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    ref.read(customAccentProvider.notifier).updateAccentColor(pickerColor);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedColor = ref.watch(customAccentProvider);
    
    // Check if the current color is a custom one (not in the default list)
    final isCustomColorSelected = !appAccentSwatches.contains(selectedColor);

    return Drawer(
      backgroundColor: cs.surface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                  ),
                  currentAccountPicture: ProfileAvatar(photoUrl: user?.photoURL),
                  accountName: Text(
                    user?.displayName ?? 'Cheq User',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  accountEmail: Text(
                    user?.email ?? '',
                    style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
                  ),
                ),
                
                ListTile(
                  leading: Icon(
                    isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: cs.primary,
                  ),
                  title: Text(
                    "Dark Mode",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  trailing: Switch(
                    value: isDarkMode,
                    activeThumbColor: cs.primary,
                    onChanged: (value) {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.palette_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 14),
                Text("App Theme Accent", style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface, fontSize: 14)),
              ],
            ),
          ),
          
          // Theme Picker Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 4, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [
                // 1. The default swatches
                ...appAccentSwatches.map((colorValue) {
                  final isCurrentChoice = selectedColor == colorValue;
                  return GestureDetector(
                    onTap: () => ref.read(customAccentProvider.notifier).updateAccentColor(colorValue),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colorValue,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCurrentChoice ? cs.onSurface : Colors.transparent,
                          width: isCurrentChoice ? 2.5 : 0,
                        ),
                        boxShadow: [
                          if (isCurrentChoice)
                            BoxShadow(color: colorValue.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)
                        ],
                      ),
                      child: isCurrentChoice 
                          ? Icon(
                              Icons.check_rounded, 
                              color: ThemeData.estimateBrightnessForColor(colorValue) == Brightness.dark 
                                  ? Colors.white 
                                  : Colors.black, 
                              size: 14,
                            )
                          : null,
                    ),
                  );
                }),

                // 2. The Custom Color Wheel Button
                GestureDetector(
                  onTap: () => _showColorPickerDialog(context, ref, selectedColor),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const SweepGradient(
                        colors: [
                          Colors.red,
                          Colors.yellow,
                          Colors.green,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ],
                      ),
                      border: Border.all(
                        color: isCustomColorSelected ? cs.onSurface : Colors.transparent,
                        width: isCustomColorSelected ? 2.5 : 0,
                      ),
                      boxShadow: [
                        if (isCustomColorSelected)
                          BoxShadow(color: selectedColor.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)
                      ],
                    ),
                    child: isCustomColorSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: ThemeData.estimateBrightnessForColor(selectedColor) == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                            size: 14,
                          )
                        : Icon(
                            Icons.colorize_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 14,
                          ),
                  ),
                ),
              ],
            ),
          ),
              
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: Icon(
                Icons.logout_rounded,
                color: cs.error,
              ),
              title: Text(
                "Sign Out",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.error,
                ),
              ),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to log out of Cheq?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Log Out'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  Navigator.pop(context);
                  await FirebaseAuth.instance.signOut();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}