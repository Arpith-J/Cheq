import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'providers/theme_provider.dart'; 
import 'providers/custom_theme_provider.dart';
import '../services/notification_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

void main() async {
  // 1. Initialize Flutter bindings so native code can be called
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Load preferences instantly
  final prefs = await SharedPreferences.getInstance();
  
  // 3. Boot heavy services in the background while the OS holds your native splash screen!
  try {
    await Future.wait([
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      NotificationService.instance.initialize(),
    ]).timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint("Core initialization exception or timeout caught: $e");
  }

  // 4. Paint the app. The native black splash screen vanishes exactly on this line.
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
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