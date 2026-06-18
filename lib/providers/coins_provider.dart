// lib/providers/coins_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live StreamProvider that listens directly to the user's Firestore document
/// and watches the 'coins' field in real-time.
final coinsProvider = StreamProvider<int>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  
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
});