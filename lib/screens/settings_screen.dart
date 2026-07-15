// lib/screens/settings_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../providers/notification_settings_provider.dart';
import '../widgets/theme_picker_row.dart';
import '../widgets/settings/ai_settings_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // 🌟 Dynamic Salutation Logic based on the user's picked time
  String _getSalutation(TimeOfDay time) {
    if (time.hour >= 4 && time.hour < 12) return "morning";
    if (time.hour >= 12 && time.hour < 16) return "afternoon";
    if (time.hour >= 16 && time.hour < 20) return "evening";
    return "night";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;
    
    final notifConfig = ref.watch(notificationSettingsProvider);
    final notifNotifier = ref.read(notificationSettingsProvider.notifier);

    // Extract user's first name for the notification preview
    final user = FirebaseAuth.instance.currentUser;
    final firstName = user?.displayName?.split(' ').first ?? 'User';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // ── APPEARANCE SECTION ──
          Text(
            "Appearance",
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                  title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Switch.adaptive(
                    value: isDarkMode,
                    activeColor: cs.primary,
                    onChanged: (value) => ref.read(themeModeProvider.notifier).toggleTheme(),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  activeColor: cs.primary,
                  title: const Text("Pending Task Badges", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("Show a red counter on the calendar for unfinished tasks."),
                  value: notifConfig.showTaskBadges,
                  onChanged: (val) => notifNotifier.toggleTaskBadges(val),
                  secondary: const Icon(Icons.looks_one_rounded, color: Colors.redAccent),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("App Theme Accent", style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 16),
                      ThemePickerRow(), // 🌟 Your modular colour picker!
                      
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                AiSettingsCard(),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── DAILY BRIEFINGS SECTION ──
          Text(
            "Daily Briefings",
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                // Morning Overview Toggle
                SwitchListTile.adaptive(
                  activeColor: cs.primary,
                  title: const Text("Morning Overview", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("Good ${_getSalutation(notifConfig.morningTime)} $firstName, you have tasks today."),
                  value: notifConfig.morningEnabled,
                  onChanged: (val) => notifNotifier.toggleMorning(val),
                  secondary: const Icon(Icons.wb_sunny_rounded, color: Colors.orange),
                ),
                // Morning Time Picker (Only shows if enabled)
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: notifConfig.morningEnabled
                      ? ListTile(
                          contentPadding: const EdgeInsets.only(left: 72, right: 16),
                          title: const Text("Delivery Time"),
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: notifConfig.morningTime,
                              );
                              if (picked != null) notifNotifier.updateMorningTime(picked);
                            },
                            child: Text(notifConfig.morningTime.format(context)),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const Divider(height: 1, indent: 16, endIndent: 16),

                // Evening Review Toggle
                SwitchListTile.adaptive(
                  activeColor: cs.primary,
                  title: const Text("Evening Review", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("Good ${_getSalutation(notifConfig.eveningTime)} $firstName, let's review your day."),
                  value: notifConfig.eveningEnabled,
                  onChanged: (val) => notifNotifier.toggleEvening(val),
                  secondary: const Icon(Icons.nights_stay_rounded, color: Colors.indigoAccent),
                ),
                // Evening Time Picker (Only shows if enabled)
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: notifConfig.eveningEnabled
                      ? ListTile(
                          contentPadding: const EdgeInsets.only(left: 72, right: 16),
                          title: const Text("Delivery Time"),
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: notifConfig.eveningTime,
                              );
                              if (picked != null) notifNotifier.updateEveningTime(picked);
                            },
                            child: Text(notifConfig.eveningTime.format(context)),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}