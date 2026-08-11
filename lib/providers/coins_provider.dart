// lib/providers/coins_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Live StreamProvider that listens directly to the user's Firestore document
/// and watches the 'coins' field in real-time.
///
/// Reacts to the auth state stream instead of snapshotting
/// `FirebaseAuth.instance.currentUser` once: on a fresh install the session is
/// restored asynchronously, and a non-autoDispose StreamProvider built with a
/// null user would otherwise cache a permanent `Stream.value(0)`.
final coinsProvider = StreamProvider<int>((ref) {
  return ref.watch(authStateProvider).when(
        data: (user) {
          // If no user is logged in yet, stream a starting value of 0
          if (user == null) return Stream.value(0);

          return FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots()
              .map((snapshot) {
                if (!snapshot.exists || snapshot.data() == null) return 0;

                final data = snapshot.data()!;
                return (data['coins'] as int?) ?? 0;
              });
        },
        loading: () => Stream.value(0),
        error: (_, __) => Stream.value(0),
      );
});