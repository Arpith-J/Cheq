// lib/providers/custom_theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';

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
    return appAccentSwatches.first;
  }

  void updateAccentColor(Color newColor) {
    state = newColor;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Convert the color to a readable Hex string (e.g., "ff4caf50")
      final hexString = newColor.value.toRadixString(16);
      FirestoreService.instance.saveUserSettings(uid, {
        'themeColorHex': hexString,
      });
    }
  }

  Future<void> loadSettings(String uid) async {
    final settings = await FirestoreService.instance.getUserSettings(uid);
    if (settings != null && settings['themeColorHex'] != null) {
      try {
        final hexInt = int.parse(settings['themeColorHex'], radix: 16);
        state = Color(hexInt);
      } catch (e) {
        debugPrint("Error parsing saved theme color: $e");
      }
    }
  }
}