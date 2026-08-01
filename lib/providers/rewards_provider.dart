// lib/providers/rewards_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

// ---------------------------------------------------------------------------
// Economy Constants
// ---------------------------------------------------------------------------

const int todoItemCoins = 5;
const int todoListCompletionCoins = 10;
const int plannerBaseCoins = 10;
const int plannerDeepWorkBonusCoins = 25;

// ---------------------------------------------------------------------------
// Badge IDs
// ---------------------------------------------------------------------------

const String nightOwlBadge = 'Night Owl';
const String scholarBadge = 'The Scholar';
const String unbreakableBadge = 'Unbreakable';

// ---------------------------------------------------------------------------
// Live stream of the user's economy document
// ---------------------------------------------------------------------------

final userStreamProvider = StreamProvider<UserModel>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value(const UserModel(uid: '', displayName: '', email: ''));
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          return UserModel(
            uid: user.uid,
            displayName: user.displayName ?? '',
            email: user.email ?? '',
          );
        }
        return UserModel.fromMap(snapshot.data()!);
      });
});

// ---------------------------------------------------------------------------
// RewardsNotifier — single home for all coin/badge logic
// ---------------------------------------------------------------------------

class RewardsNotifier extends Notifier<UserModel> {
  @override
  UserModel build() {
    final asyncUser = ref.watch(userStreamProvider);
    return asyncUser.value ??
        const UserModel(uid: '', displayName: '', email: '');
  }

  /// Daily Planner task completion.
  /// +10 base coins, +25 "Deep Work" bonus when the task runs >= 2 hours,
  /// and unlocks the "Night Owl" badge when the task ends at/after 10 PM.
  /// The exact reward is persisted onto the task (`coinsAwarded`) BEFORE the
  /// user's balance is updated so it can be precisely revoked on uncheck.
  Future<void> awardPlannerTaskCompletion(PlannerModel entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    var reward = plannerBaseCoins;
    if (entry.endTime.difference(entry.startTime) >= const Duration(hours: 2)) {
      reward += plannerDeepWorkBonusCoins;
    }

    final badges = <String>[
      if (entry.endTime.hour >= 22) nightOwlBadge,
    ];

    await FirestoreService.instance
        .saveTask(entry.copyWith(coinsAwarded: reward, isRewarded: true));

    await _commit(uid, reward, badges);
  }

  /// Reverses a Daily Planner task reward when it is unchecked.
  /// Deducts the exact amount that was originally awarded and resets
  /// `coinsAwarded` back to 0 so a future re-check re-awards cleanly.
  Future<void> revokePlannerTaskCompletion(PlannerModel entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || entry.coinsAwarded <= 0) return;

    await FirestoreService.instance
        .saveTask(entry.copyWith(coinsAwarded: 0, isRewarded: false));

    await _commit(uid, -entry.coinsAwarded, const []);
  }

  /// Individual To-Do item completion: flat +5 coins.
  Future<void> awardTodoCompletion() =>
      _commit(FirebaseAuth.instance.currentUser?.uid, todoItemCoins, const []);

  /// Completing an entire To-Do list: flat +10 coins.
  Future<void> awardTodoListCompletion() => _commit(
        FirebaseAuth.instance.currentUser?.uid,
        todoListCompletionCoins,
        const [],
      );

  /// Reverses an individual To-Do item reward when it is unchecked.
  Future<void> deductTodoCompletion() =>
      _commit(FirebaseAuth.instance.currentUser?.uid, -todoItemCoins, const []);

  /// Reverses the To-Do list completion bonus when a completed list is reopened.
  Future<void> deductTodoListCompletion() => _commit(
        FirebaseAuth.instance.currentUser?.uid,
        -todoListCompletionCoins,
        const [],
      );

  Future<void> _commit(String? uid, int coinDelta, List<String> badges) async {
    if (uid == null) return;

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final updates = <String, dynamic>{
        'coins': FieldValue.increment(coinDelta),
      };
      for (final badge in badges) {
        updates['unlockedBadges'] = FieldValue.arrayUnion([badge]);
      }
      await userRef.set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Rewards commit failed: $e');
    }
  }
}

final rewardsProvider = NotifierProvider<RewardsNotifier, UserModel>(
  RewardsNotifier.new,
);
