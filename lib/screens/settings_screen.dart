// lib/screens/settings_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../providers/notification_settings_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/theme_picker_row.dart';
import '../widgets/settings/ai_settings_card.dart';
import '../providers/task_settings_provider.dart';
import '../screens/category_manager_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // Dynamic Salutation Logic based on the user's picked time
  String _getSalutation(TimeOfDay time) {
    if (time.hour >= 4 && time.hour < 12) return "morning";
    if (time.hour >= 12 && time.hour < 16) return "afternoon";
    if (time.hour >= 16 && time.hour < 20) return "evening";
    return "night";
  }

  void _showEditNameDialog(BuildContext context, User? user) {
    final controller = TextEditingController(
      text: user?.displayName ?? '',
    );
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Your name',
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => _saveName(ctx, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _saveName(ctx, controller),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveName(BuildContext ctx, TextEditingController controller) async {
    final name = controller.text.trim();
    if (name.isEmpty) return;

    await FirestoreService.instance.updateDisplayName(name);
    if (ctx.mounted) Navigator.pop(ctx);
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
          // ── PROFILE SECTION ──
          Text(
            "Profile",
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
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person_rounded, color: cs.primary),
              ),
              title: Text(
                user?.displayName ?? 'No name set',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(user?.email ?? ''),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showEditNameDialog(context, user),
            ),
          ),

          const SizedBox(height: 32),

          // ── APPEARANCES SECTION ──
          Text(
            "Appearances",
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
                    activeTrackColor: cs.primary,
                    onChanged: (value) => ref.read(themeModeProvider.notifier).toggleTheme(),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("App Theme Accent", style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 16),
                      ThemePickerRow(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── PREFERENCES SECTION ──
          Text(
            "Preferences",
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
                SwitchListTile.adaptive(
                  activeTrackColor: cs.primary,
                  title: const Text("Pending Task Badges", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("Show a red counter on the calendar for unfinished tasks."),
                  value: notifConfig.showTaskBadges,
                  onChanged: (val) => notifNotifier.toggleTaskBadges(val),
                  secondary: const Icon(Icons.looks_one_rounded, color: Colors.redAccent),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  activeTrackColor: cs.primary,
                  title: const Text('Carry Over Pending Tasks', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Automatically move unfinished tasks from past days to today.'),
                  secondary: Icon(Icons.next_plan_rounded, color: cs.primary),
                  value: ref.watch(carryOverTasksProvider),
                  onChanged: (val) {
                    ref.read(carryOverTasksProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  activeTrackColor: cs.primary,
                  title: const Text('Show Group Tasks on Main Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Merge tasks from your Spaces into the Planner and To-Do lists.'),
                  secondary: Icon(Icons.groups_rounded, color: cs.primary),
                  value: ref.watch(showGroupTasksProvider),
                  onChanged: (val) {
                    ref.read(showGroupTasksProvider.notifier).toggle(val);
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.category_rounded),
                  title: const Text("Manage Categories", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("Create and color-code your tasks"),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => const CategoryManagerSheet(),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  activeTrackColor: cs.primary,
                  title: const Text("Morning Overview", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("Good ${_getSalutation(notifConfig.morningTime)} $firstName, you have tasks today."),
                  value: notifConfig.morningEnabled,
                  onChanged: (val) => notifNotifier.toggleMorning(val),
                  secondary: const Icon(Icons.wb_sunny_rounded, color: Colors.orange),
                ),
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
                SwitchListTile.adaptive(
                  activeTrackColor: cs.primary,
                  title: const Text("Evening Review", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("Good ${_getSalutation(notifConfig.eveningTime)} $firstName, let's review your day."),
                  value: notifConfig.eveningEnabled,
                  onChanged: (val) => notifNotifier.toggleEvening(val),
                  secondary: const Icon(Icons.nights_stay_rounded, color: Colors.indigoAccent),
                ),
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

          const SizedBox(height: 32),

          // ── SMART ASSISTANT SECTION ──
          Text(
            "Smart Assistant",
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
            child: const Column(
              children: [
                AiSettingsCard(),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}