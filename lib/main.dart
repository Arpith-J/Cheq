import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/firestore_service.dart';
import 'providers/coins_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/notification_settings_provider.dart'; 
import 'providers/planner_provider.dart';
import 'providers/rewards_provider.dart';
import 'services/notification_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

void main() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Register the Dart callback that completes tasks when a home screen
  //    widget checkbox is tapped (fires in a background isolate).
  HomeWidget.registerBackgroundCallback(backgroundCallback);

  // 3. Load preferences instantly
  final prefs = await SharedPreferences.getInstance();
  
  // 4. Boot Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // 5. AWAIT notifications so timezones and channels are fully locked in BEFORE the app loads data
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint("Notification initialization failed: $e");
  }

  //  6. CREATE STANDALONE RIVERPOD CONTAINER
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );

  // 7. PRE-WARM THE UI STATE (Prevents Layout Shift / Pop-in)
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      // A. Load user preferences instantly
      container.read(customAccentProvider.notifier).loadSettings(user.uid);
      container.read(notificationSettingsProvider.notifier).loadSettings(user.uid);
      container.read(themeModeProvider.notifier).loadSettings(user.uid);
      // B. Explicitly fetch the cloud UserModel and hydrate the local
      //    economy/stats/badge providers before the first frame, so a fresh
      //    install never renders a Trophy Room or coin balance of 0.
      final cloudModel =
          await FirestoreService.instance.getUserModel(user.uid);
      if (cloudModel != null) {
        container.read(rewardsProvider.notifier).hydrateFromCloud(cloudModel);
      }
      // C. Kick off the live coins/economy streams so the AppBar coin pill and
      //    Trophy Room already have a subscription in flight.
      container.read(coinsProvider);
      container.read(userStreamProvider);
      // D. Force Firestore to load local task cache BEFORE drawing the screen
      // We give it a tiny 500ms timeout just in case, so it never freezes the app.
      final tasks = await container.read(firestorePlannerStreamProvider.future)
          .timeout(const Duration(milliseconds: 500));
      // E. Silently evaluate the "Clean Slate" badge in the background.
      unawaited(
        container.read(rewardsProvider.notifier).evaluateCleanSlateBadge(tasks),
      );
    } catch (e) {
      debugPrint("Pre-warm timeout/error (safe to ignore): $e");
    }
  }

  // 8. Paint the app with the fully loaded state. 
  // The native splash screen drops exactly here, revealing perfect data!
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CheqApp(),
    ),
  );
}

// ── ROOT APPLICATION COMPONENT ──────────────────
class CheqApp extends ConsumerWidget {
  const CheqApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appTheme = ref.watch(appThemeProvider);

    return MaterialApp(
      title: const String.fromEnvironment('APP_NAME', defaultValue: 'Ariadne'),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: appTheme.light,
      darkTheme: appTheme.dark,
      home: const AuthGate(),
    );
  }
}