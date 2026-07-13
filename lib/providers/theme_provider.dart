// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';

// The Riverpod 3.x compliant theme notifier
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light; // Baseline starting theme

  void toggleTheme() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    
    // 🌟 Save the choice to Firebase immediately
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.saveUserSettings(uid, {
        'isDarkMode': state == ThemeMode.dark,
      });
    }
  }

  // 🌟 Load it on app boot
  Future<void> loadSettings(String uid) async {
    final settings = await FirestoreService.instance.getUserSettings(uid);
    if (settings != null && settings.containsKey('isDarkMode')) {
      state = (settings['isDarkMode'] as bool) ? ThemeMode.dark : ThemeMode.light;
    }
  }
}