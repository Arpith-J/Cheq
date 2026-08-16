// lib/widgets/app_side_drawer.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/main_scaffold.dart'; // To access the ProfileAvatar widget
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/trophy_room_screen.dart';
import '../screens/bundles_screen.dart';
import '../screens/constellation_screen.dart';

const String appName = String.fromEnvironment('APP_NAME', defaultValue: 'Cheq');
class AppSideDrawer extends ConsumerWidget {
  const AppSideDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme; 

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
                // ── Settings ──────────────────────────────────────────────
                ListTile(
                  leading: Icon(Icons.settings_rounded, color: cs.primary),
                  title: const Text(
                    "Settings",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    // Close the drawer first
                    Navigator.pop(context); 
                    // Slide in the full Settings Screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.emoji_events_rounded, color: cs.primary),
                  title: const Text(
                    "Trophy Room",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrophyRoomScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.pie_chart_rounded, color: cs.primary),
                  title: const Text(
                    "Time Breakdown",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatsScreen()),
                    );
                  },
                ),
                // ── Rewards dropdown (Bundles + Constellation) ────────────
                ExpansionTile(
                  leading: Icon(Icons.redeem_rounded, color: cs.primary),
                  iconColor: cs.primary,
                  collapsedIconColor: cs.primary,
                  title: const Text(
                    "Rewards",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    ListTile(
                      leading: Icon(Icons.palette_outlined, color: cs.primary),
                      title: const Text(
                        "Bundles",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text("Theme packs"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BundlesScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.auto_awesome, color: cs.primary),
                      title: const Text(
                        "Constellation",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text("Star data core"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ConstellationScreen()),
                        );
                      },
                    ),
                  ],
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
                    content: const Text('Are you sure you want to log out of $appName?'),
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