// lib/providers/rewards_provider.dart

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../models/star_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/home_widget_service.dart';
import '../theme/app_themes.dart';
import 'auth_provider.dart';
import 'planner_provider.dart';

// ---------------------------------------------------------------------------
// Economy Constants
// ---------------------------------------------------------------------------

const int todoItemCoins = 5;
const int todoListCompletionCoins = 10;
const int plannerBaseCoins = 10;
const int plannerDeepWorkBonusCoins = 25;
const int perfectDayBonusCoins = 50;
const int cleanSlateBonusCoins = 200;

/// Cost of each star category in the Constellation Data Core.
const Map<String, int> starCosts = {
  'focus': 75,
  'creativity': 100,
  'academic': 125,
};

final Random _random = Random();

// ---------------------------------------------------------------------------
// Badge IDs
// ---------------------------------------------------------------------------

const String nightOwlBadge = 'Night Owl';
const String scholarBadge = 'The Scholar';
const String unbreakableBadge = 'Unbreakable';
const String cleanSlateBadge = 'Clean Slate';

// ---------------------------------------------------------------------------
// Widget Skin catalog
// ---------------------------------------------------------------------------

class WidgetSkinEntry {
  final String id;
  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final Color previewBackground;
  final Color previewAccent;

  const WidgetSkinEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.previewBackground,
    required this.previewAccent,
  });
}

const WidgetSkinEntry defaultWidgetSkinEntry = WidgetSkinEntry(
  id: 'default',
  name: 'Default',
  description: 'The classic dark widget panel.',
  cost: 0,
  icon: Icons.grid_view_rounded,
  previewBackground: Color(0xFF101010),
  previewAccent: Color(0xFF4caf50),
);

const WidgetSkinEntry glassWidgetSkinEntry = WidgetSkinEntry(
  id: 'glass',
  name: 'Glassmorphism',
  description: 'Frosted glass with a translucent backdrop.',
  cost: 800,
  icon: Icons.blur_on_rounded,
  previewBackground: Color(0x80000000),
  previewAccent: Color(0xFFCFE3FF),
);

const WidgetSkinEntry amoledWidgetSkinEntry = WidgetSkinEntry(
  id: 'amoled',
  name: 'Midnight AMOLED',
  description: 'Pure black panel for deep power-saving blacks.',
  cost: 800,
  icon: Icons.dark_mode_outlined,
  previewBackground: Color(0xFF000000),
  previewAccent: Color(0xFF66BB6A),
);

const List<WidgetSkinEntry> widgetSkinCatalog = [
  defaultWidgetSkinEntry,
  glassWidgetSkinEntry,
  amoledWidgetSkinEntry,
];

WidgetSkinEntry? widgetSkinEntryById(String id) {
  for (final entry in widgetSkinCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Live stream of the user's economy document
// ---------------------------------------------------------------------------

/// Live stream of the user's economy document, reacted to the auth state so it
/// re-subscribes with the signed-in user the moment a login completes. Without
/// this, a provider built while `FirebaseAuth.currentUser` was still null (a
/// fresh install before the session restore finishes) caches an empty
/// [UserModel] forever and the Trophy Room / stats / constellation stay at 0.
final userStreamProvider = StreamProvider<UserModel>((ref) {
  return ref.watch(authStateProvider).when(
        data: (user) {
          if (user == null) {
            return Stream.value(
              const UserModel(uid: '', displayName: '', email: ''),
            );
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
        },
        loading: () => Stream.value(
          const UserModel(uid: '', displayName: '', email: ''),
        ),
        error: (_, __) => Stream.value(
          const UserModel(uid: '', displayName: '', email: ''),
        ),
      );
});

// ---------------------------------------------------------------------------
// RewardsNotifier — single home for all coin/badge logic
// ---------------------------------------------------------------------------

class RewardsNotifier extends Notifier<UserModel> {
  @override
  UserModel build() {
    final asyncUser = ref.watch(userStreamProvider);
    final user = asyncUser.value ??
        const UserModel(uid: '', displayName: '', email: '');

    // Keep the native widget's skin cache in sync with Firestore so the
    // home screen widget always renders with the user's active skin.
    if (asyncUser.value != null) {
      HomeWidgetService.activeWidgetSkin = user.activeWidgetSkin;
    }
    return user;
  }

  /// Explicitly seeds local state from a freshly fetched cloud [UserModel].
  /// Invoked on app boot / login so the Trophy Room, coin pill, badges,
  /// constellation and streaks render the persisted Firestore data immediately
  /// instead of waiting (or never) on the snapshots stream's first event.
  void hydrateFromCloud(UserModel model) {
    state = model;
  }

  /// Daily Planner task completion.
  /// +10 base coins, +25 "Deep Work" bonus when the task runs >= 2 hours,
  /// and unlocks the "Night Owl" badge when the task ends at/after 10 PM.
  /// The exact reward is persisted onto the task (`coinsAwarded`) BEFORE the
  /// user's balance is updated so it can be precisely revoked on uncheck.
  /// The task's real duration is banked into `totalMinutesLogged` and the
  /// permanent stats ledgers (`categoryMinutes` + `dailyActivityLog` +
  /// `dailyMinutesLog`) so the lifetime stats survive task deletion.
  Future<void> awardPlannerTaskCompletion(PlannerModel entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    var reward = plannerBaseCoins;
    if (_calculateSafeMinutes(entry.startTime, entry.endTime) >= 120) {
      reward += plannerDeepWorkBonusCoins;
    }

    final badges = <String>[
      if (entry.endTime.hour >= 22) nightOwlBadge,
    ];

    final minutes = _durationMinutes(entry);
    final category = entry.categoryName ?? 'Uncategorized';
    final today = _dateKey(DateTime.now());

    await FirestoreService.instance
        .saveTask(entry.copyWith(coinsAwarded: reward, isRewarded: true));

    await _commit(
      uid,
      reward,
      badges,
      minutesDelta: minutes,
      categoryMinuteDeltas: {category: minutes},
      dailyActivityDeltas: {today: 1},
      dailyMinuteDeltas: {_dateKey(entry.startTime): minutes},
    );
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
  /// The banked minutes, category minutes, and daily activity count are also
  /// reversed to prevent stat farming.
  Future<void> revokePlannerTaskCompletion(PlannerModel entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || entry.coinsAwarded <= 0) return;

    final minutes = _durationMinutes(entry);
    final category = entry.categoryName ?? 'Uncategorized';
    final today = _dateKey(DateTime.now());

    await FirestoreService.instance
        .saveTask(entry.copyWith(coinsAwarded: 0, isRewarded: false));

    await _commit(
      uid,
      -entry.coinsAwarded,
      const [],
      minutesDelta: -minutes,
      categoryMinuteDeltas: {category: -minutes},
      dailyActivityDeltas: {today: -1},
      dailyMinuteDeltas: {_dateKey(entry.startTime): -minutes},
    );
  }

  /// Individual To-Do item completion: flat +5 coins and +1 to the daily
  /// activity ledger (todo items have no category or duration).
  Future<void> awardTodoCompletion() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _commit(
      uid,
      todoItemCoins,
      const [],
      dailyActivityDeltas: {_dateKey(DateTime.now()): 1},
    );
  }

  /// Completing an entire To-Do list: flat +10 coins.
  Future<void> awardTodoListCompletion() => _commit(
        FirebaseAuth.instance.currentUser?.uid,
        todoListCompletionCoins,
        const [],
      );

  /// Reverses an individual To-Do item reward when it is unchecked, removing
  /// its daily activity entry too.
  Future<void> deductTodoCompletion() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _commit(
      uid,
      -todoItemCoins,
      const [],
      dailyActivityDeltas: {_dateKey(DateTime.now()): -1},
    );
  }

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
  /// follows the user across devices. No-op if the theme isn't owned. The
  /// unlocked list is re-read from Firestore so a freshly purchased theme can
  /// be equipped immediately, and the free 'default' theme always equips —
  /// clearing any premium bundle override so the app falls back to the
  /// system-brightness theme built from the user's selected accent color.
  Future<bool> equipTheme(String themeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      // The free 'default' theme is always owned and never requires the unlock
      // check. Equipping it simply clears the premium override back to the
      // stock theme resolved from the accent color + system brightness.
      if (themeId == themeIdDefault) {
        await userRef.set(
          {'activeTheme': themeIdDefault},
          SetOptions(merge: true),
        );
        return true;
      }

      final snapshot = await userRef.get();
      final data = snapshot.data();
      if (data == null) return false;

      final unlockedThemes =
          (data['unlockedThemes'] as List<dynamic>? ?? const [])
              .cast<String>();
      if (!unlockedThemes.contains(themeId)) return false;

      await userRef.set({'activeTheme': themeId}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Theme equip failed: $e');
      return false;
    }
  }

  /// Purchases a widget skin. Atomically verifies the balance inside a
  /// Firestore transaction so two devices can never overspend. Returns `true`
  /// when the skin was unlocked (or already owned), `false` when
  /// unaffordable/invalid.
  Future<bool> purchaseWidgetSkin(String skinId, int cost) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final entry = widgetSkinEntryById(skinId);
    if (entry == null || entry.cost <= 0) return false;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final unlocked = await FirebaseFirestore.instance.runTransaction(
        (tx) async {
          final snap = await tx.get(userRef);
          final data = snap.data();
          if (data == null) return false;

          final coins = (data['coins'] as int?) ?? 0;
          final unlockedSkins =
              (data['unlockedWidgetSkins'] as List<dynamic>? ?? const [])
                  .cast<String>();

          if (unlockedSkins.contains(skinId)) return true;
          if (coins < cost) return false;

          tx.update(userRef, {
            'coins': FieldValue.increment(-cost),
            'unlockedWidgetSkins': FieldValue.arrayUnion([skinId]),
          });
          return true;
        },
      );
      return unlocked;
    } catch (e) {
      debugPrint('Widget skin purchase failed: $e');
      return false;
    }
  }

  /// Equips an unlocked widget skin, persisting the choice to Firestore so it
  /// follows the user across devices, then instantly re-syncs the native home
  /// screen widget with the new skin. No-op if the skin isn't owned. The
  /// unlocked list is re-read from Firestore so a freshly purchased skin can be
  /// equipped immediately, and the free 'default' skin always equips (reverting
  /// the native widget back to its base state).
  Future<bool> equipWidgetSkin(String skinId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final snapshot = await userRef.get();
      final data = snapshot.data();
      if (data == null) return false;

      final unlockedSkins =
          (data['unlockedWidgetSkins'] as List<dynamic>? ?? const [])
              .cast<String>();
      if (!unlockedSkins.contains(skinId)) return false;

      await userRef.set({'activeWidgetSkin': skinId}, SetOptions(merge: true));

      // Push the new skin to the native widget immediately.
      HomeWidgetService.activeWidgetSkin = skinId;
      final tasks = ref.read(firestorePlannerStreamProvider).value ??
          const <PlannerModel>[];
      unawaited(HomeWidgetService.updateHomeScreenWidgets(
        tasks: tasks,
        widgetSkin: skinId,
      ));
      return true;
    } catch (e) {
      debugPrint('Widget skin equip failed: $e');
      return false;
    }
  }

  /// Purchases a star for the Constellation Data Core. Looks up the
  /// category-specific cost, verifies the balance inside a Firestore
  /// transaction, deducts the exact amount, and appends a randomly positioned
  /// star to the user's `constellation`. Returns `true` when the star was
  /// bought, `false` when the user can't afford it or the category is unknown.
  Future<bool> purchaseStar(String category) async {
    final cost = starCosts[category];
    if (cost == null) return false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final purchased = await FirebaseFirestore.instance.runTransaction(
        (tx) async {
          final snap = await tx.get(userRef);
          final data = snap.data();
          if (data == null) return false;

          final coins = (data['coins'] as int?) ?? 0;
          if (coins < cost) return false;

          final star = StarModel(
            id: 'star_${DateTime.now().millisecondsSinceEpoch}_'
                '${_random.nextInt(9999)}',
            category: category,
            // Normalized coordinates within the visible canvas (0.15–0.85) so
            // even edge stars never drift off-screen.
            dx: 0.15 + _random.nextDouble() * 0.7,
            dy: 0.15 + _random.nextDouble() * 0.7,
          );

          tx.update(userRef, {
            'coins': FieldValue.increment(-cost),
            'constellation': FieldValue.arrayUnion([star.toMap()]),
          });
          return true;
        },
      );
      return purchased;
    } catch (e) {
      debugPrint('Star purchase failed: $e');
      return false;
    }
  }

  /// Optimistically relocates a star in local state so the constellation
  /// repaints live under the user's finger while paused. The permanent
  /// Firestore write happens in [moveStar] when the drag ends.
  void previewStarMove(String starId, double dx, double dy) {
    final idx = state.constellation.indexWhere((s) => s.id == starId);
    if (idx < 0) return;
    state = state.copyWith(
      constellation: [
        for (var i = 0; i < state.constellation.length; i++)
          i == idx
              ? state.constellation[i].copyWith(dx: dx, dy: dy)
              : state.constellation[i],
      ],
    );
  }

  /// Persists a star's new normalized position (0–1) to Firestore atomically
  /// so the rearranged constellation follows the user across devices.
  Future<void> moveStar(String starId, double dx, double dy) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final data = snap.data();
        if (data == null) return;

        final constellation = (data['constellation'] as List<dynamic>? ?? const [])
            .map((e) => StarModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();

        final idx = constellation.indexWhere((s) => s.id == starId);
        if (idx < 0) return;

        constellation[idx] = constellation[idx].copyWith(dx: dx, dy: dy);
        tx.update(userRef, {
          'constellation': constellation.map((s) => s.toMap()).toList(),
        });
      });
    } catch (e) {
      debugPrint('Star move failed: $e');
    }
  }

  Future<void> _commit(
    String? uid,
    int coinDelta,
    List<String> badges, {
    int minutesDelta = 0,
    Map<String, int> categoryMinuteDeltas = const {},
    Map<String, int> dailyActivityDeltas = const {},
    Map<String, int> dailyMinuteDeltas = const {},
  }) async {
    if (uid == null) return;

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final updates = <String, dynamic>{
        'coins': FieldValue.increment(coinDelta),
      };
      if (minutesDelta != 0) {
        updates['totalMinutesLogged'] = FieldValue.increment(minutesDelta);
      }
      // Nested ledger paths are incremented atomically via dot-notation so the
      // permanent stats never need a read-modify-write round trip.
      for (final entry in categoryMinuteDeltas.entries) {
        updates['categoryMinutes.${entry.key}'] =
            FieldValue.increment(entry.value);
      }
      for (final entry in dailyActivityDeltas.entries) {
        updates['dailyActivityLog.${entry.key}'] =
            FieldValue.increment(entry.value);
      }
      for (final entry in dailyMinuteDeltas.entries) {
        updates['dailyMinutesLog.${entry.key}'] =
            FieldValue.increment(entry.value);
      }
      for (final badge in badges) {
        updates['unlockedBadges'] = FieldValue.arrayUnion([badge]);
      }
      await userRef.update(updates);
    } catch (e) {
      debugPrint('Rewards commit failed: $e');
    }
  }
}

/// Returns the real duration of a planner entry in whole minutes, mirroring the
/// UI's "runs past midnight" handling (an end time before the start time rolls
/// into the next day).
int _durationMinutes(PlannerModel entry) =>
    _calculateSafeMinutes(entry.startTime, entry.endTime);

int _calculateSafeMinutes(DateTime startTime, DateTime endTime) {
  DateTime safeEndTime = endTime.isBefore(startTime)
      ? endTime.add(const Duration(days: 1))
      : endTime;
  int rawMinutes = safeEndTime.difference(startTime).inMinutes;
  return rawMinutes < 0 ? 0 : rawMinutes;
}

/// Formats a date as a 'YYYY-MM-DD' string for the `dailyActivityLog` ledger.
String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

final rewardsProvider = NotifierProvider<RewardsNotifier, UserModel>(
  RewardsNotifier.new,
);
