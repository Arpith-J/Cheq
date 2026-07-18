// lib/providers/custom_theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../main.dart';

const List<Color> appAccentSwatches = [
  Color(0xff4caf50), // 0. Default Cheq Green
  Color(0xFF2196F3), // 1. Electric Blue
  Color(0xFF9C27B0), // 2. Vivid Purple
  Color(0xFFFF9800), // 3. Energetic Orange
  Color(0xFFE91E63), // 4. Rose Pink
  Color(0xFF96F3E1), // 5. Mint Teal
];

final customAccentProvider = NotifierProvider<CustomAccentNotifier, Color>(
  CustomAccentNotifier.new,
);

class CustomAccentNotifier extends Notifier<Color> {
  @override
  Color build() {
    // 1. Instantly load the cached color on boot (Zero network delay = zero flash!)
    final prefs = ref.watch(sharedPrefsProvider);
    final hexString = prefs.getString('themeColorHex');

    if (hexString != null) {
      return Color(int.parse(hexString, radix: 16));
    }
    return appAccentSwatches.first;
  }

  void updateAccentColor(Color newColor) {
    state = newColor;
    final hexString = newColor.value.toRadixString(16);
    
    // 2. Save it locally immediately so it's ready for the next app launch
    ref.read(sharedPrefsProvider).setString('themeColorHex', hexString);

    // 3. Keep your existing background sync to Firebase
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.saveUserSettings(uid, {
        'themeColorHex': hexString,
      });
    }
  }

  // 4. Update your load method to ensure cloud changes sync down to local storage
  Future<void> loadSettings(String uid) async {
    final settings = await FirestoreService.instance.getUserSettings(uid);
    if (settings != null && settings.containsKey('themeColorHex')) {
      final hexString = settings['themeColorHex'] as String;
      state = Color(int.parse(hexString, radix: 16));
      
      // Sync cloud truth to local cache
      ref.read(sharedPrefsProvider).setString('themeColorHex', hexString);
    }
  }
}