import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'providers/theme_provider.dart'; 
import 'providers/custom_theme_provider.dart';
import 'providers/notification_settings_provider.dart'; 
import 'providers/planner_provider.dart';
import '../services/notification_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

void main() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Load preferences instantly
  final prefs = await SharedPreferences.getInstance();
  
  // 3. Boot Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // 4. AWAIT notifications so timezones and channels are fully locked in BEFORE the app loads data
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint("Notification initialization failed: $e");
  }

  //  5. CREATE STANDALONE RIVERPOD CONTAINER
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );

  // 6. PRE-WARM THE UI STATE (Prevents Layout Shift / Pop-in)
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      // A. Load user preferences instantly
      container.read(customAccentProvider.notifier).loadSettings(user.uid);
      container.read(notificationSettingsProvider.notifier).loadSettings(user.uid);
      container.read(themeModeProvider.notifier).loadSettings(user.uid);
      // B. Force Firestore to load local task cache BEFORE drawing the screen
      // We give it a tiny 500ms timeout just in case, so it never freezes the app.
      await container.read(firestorePlannerStreamProvider.future)
          .timeout(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint("Pre-warm timeout/error (safe to ignore): $e");
    }
  }

  // 7. Paint the app with the fully loaded state. 
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
    final currentAccent = ref.watch(customAccentProvider);

    return MaterialApp(
      title: const String.fromEnvironment('APP_NAME', defaultValue: 'Ariadne'),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode, 
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: currentAccent,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true, 
        colorScheme: ColorScheme.fromSeed(
          seedColor: currentAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}