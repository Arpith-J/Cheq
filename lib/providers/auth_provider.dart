// lib/providers/auth_provider.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream of the Firebase Auth state (`null` while signed out). Watched by the
/// data providers so they (re)subscribe to the correct user document the
/// moment a sign-in completes — even if they were first built while the
/// FirebaseAuth session was still being restored on a fresh install.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});
