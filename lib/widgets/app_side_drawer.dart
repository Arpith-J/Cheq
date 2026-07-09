// lib/widgets/app_side_drawer.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/main_scaffold.dart'; // To access the ProfileAvatar widget
import '../screens/settings_screen.dart';

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