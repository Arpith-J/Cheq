// lib/providers/rewards_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_themes.dart';

// ---------------------------------------------------------------------------
// Economy Constants
// ---------------------------------------------------------------------------

const int todoItemCoins = 5;
const int todoListCompletionCoins = 10;
const int plannerBaseCoins = 10;
const int plannerDeepWorkBonusCoins = 25;
const int perfectDayBonusCoins = 50;
const int cleanSlateBonusCoins = 200;

// ---------------------------------------------------------------------------
// Badge IDs
// ---------------------------------------------------------------------------

const String nightOwlBadge = 'Night Owl';
const String scholarBadge = 'The Scholar';
const String unbreakableBadge = 'Unbreakable';
const String cleanSlateBadge = 'Clean Slate';

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

  /// Evaluates the entire day whenever a Daily Planner task is completed.
  /// When there is at least one task and every task is done, awards the
  /// "perfect day": +50 coins and a streak increment. The streak can only
  /// advance once per calendar day (tracked via `lastPerfectDay`).
  Future<void> checkAndAwardPerfectDay(List<PlannerModel> todaysTasks) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || todaysTasks.isEmpty) return;
    if (!todaysTasks.every((task) => task.isDone)) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snapshot = await userRef.get();
      final data = snapshot.data();
      if (data == null) return;

      final lastPerfect = UserModel.fromMap(data).lastPerfectDay;
      if (lastPerfect != null &&
          lastPerfect.year == today.year &&
          lastPerfect.month == today.month &&
          lastPerfect.day == today.day) {
        return;
      }

      await userRef.set({
        'coins': FieldValue.increment(perfectDayBonusCoins),
        'streakCount': FieldValue.increment(1),
        'lastPerfectDay': Timestamp.fromDate(today),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Perfect day commit failed: $e');
    }
  }

  /// Evaluates the "Clean Slate" badge: a rolling 7-day window with zero
  /// overdue tasks. Runs at most once per calendar day (guarded by
  /// `lastCleanSlateCheck`) so it never recomputes on every screen rebuild.
  /// When earned, unlocks the badge and awards a +200 coin bonus.
  Future<void> evaluateCleanSlateBadge(
    List<PlannerModel> allHistoricalTasks,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Fast path: skip entirely if we already evaluated today.
    final cachedLastCheck = state.lastCleanSlateCheck;
    if (cachedLastCheck != null &&
        cachedLastCheck.year == today.year &&
        cachedLastCheck.month == today.month &&
        cachedLastCheck.day == today.day) {
      return;
    }

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snapshot = await userRef.get();
      final data = snapshot.data();
      if (data == null) return;

      // Re-check against Firestore so multi-device state is respected.
      final lastCheck = UserModel.fromMap(data).lastCleanSlateCheck;
      if (lastCheck != null &&
          lastCheck.year == today.year &&
          lastCheck.month == today.month &&
          lastCheck.day == today.day) {
        return;
      }

      final sevenDaysAgo = today.subtract(const Duration(days: 7));
      final yesterdayEnd = today
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 23, minutes: 59, seconds: 59));

      final tasksInLast7Days = allHistoricalTasks.where((task) {
        final taskDate = DateTime(
          task.startTime.year,
          task.startTime.month,
          task.startTime.day,
        );
        return !taskDate.isBefore(sevenDaysAgo) &&
            !taskDate.isAfter(yesterdayEnd);
      }).toList();

      final hasNoOverdueTasks = tasksInLast7Days.every(
        (task) => task.isDone || !task.endTime.isBefore(now),
      );

      if (tasksInLast7Days.isNotEmpty && hasNoOverdueTasks) {
        await userRef.set({
          'coins': FieldValue.increment(cleanSlateBonusCoins),
          'unlockedBadges': FieldValue.arrayUnion([cleanSlateBadge]),
          'lastCleanSlateCheck': Timestamp.fromDate(today),
        }, SetOptions(merge: true));
        debugPrint('Clean Slate badge unlocked: +$cleanSlateBonusCoins coins.');
      } else {
        // Remember the check even when the badge isn't earned yet so we
        // don't re-run the evaluation for the rest of today.
        await userRef.set({
          'lastCleanSlateCheck': Timestamp.fromDate(today),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Clean Slate evaluation failed: $e');
    }
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

  /// Purchases a shop theme. Atomically verifies the balance inside a Firestore
  /// transaction so two devices can never overspend. Returns `true` when the
  /// theme was unlocked (or already owned), `false` when unaffordable/invalid.
  Future<bool> purchaseTheme(String themeId, int cost) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final entry = themeEntryById(themeId);
    if (entry == null || entry.cost <= 0) return false;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final unlocked = await FirebaseFirestore.instance.runTransaction(
        (tx) async {
          final snap = await tx.get(userRef);
          final data = snap.data();
          if (data == null) return false;

          final coins = (data['coins'] as int?) ?? 0;
          final unlockedThemes =
              (data['unlockedThemes'] as List<dynamic>? ?? const [])
                  .cast<String>();

          if (unlockedThemes.contains(themeId)) return true;
          if (coins < cost) return false;

          tx.update(userRef, {
            'coins': FieldValue.increment(-cost),
            'unlockedThemes': FieldValue.arrayUnion([themeId]),
          });
          return true;
        },
      );
      return unlocked;
    } catch (e) {
      debugPrint('Theme purchase failed: $e');
      return false;
    }
  }

  /// Equips an unlocked theme, persisting the choice to Firestore so it
  /// follows the user across devices. No-op if the theme isn't owned.
  Future<bool> equipTheme(String themeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    if (!state.unlockedThemes.contains(themeId)) return false;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'activeTheme': themeId}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Theme equip failed: $e');
      return false;
    }
  }

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
