import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/firestore_service.dart';
import 'services/group_sync_service.dart';
import 'services/local_notification_service.dart';
import 'providers/coins_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/custom_theme_provider.dart';
import 'providers/notification_settings_provider.dart'; 
import 'providers/planner_provider.dart';
import 'providers/rewards_provider.dart';
import 'providers/group_sync_provider.dart';
import 'services/notification_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

// ---------------------------------------------------------------------------
// Background group-sync worker (Workmanager)
// ---------------------------------------------------------------------------

/// Unique name (and task tag) for the periodic group-sync Workmanager task.
/// Runs hourly (the Android minimum is 15 minutes).
const String groupSyncTaskName = 'hourly-group-sync';

/// Workmanager callback dispatcher — invoked in a background isolate whenever
/// a scheduled task fires. Firebase is initialized on demand inside the isolate
/// and the group sync hydrates the local offline cache from Firestore. When the
/// worker detects a genuinely NEW group task (not previously seen on this
/// device, and assigned to the user or their group), a lightweight local
/// notification is posted — no FCM involved. Failures are swallowed so the
/// worker always returns a completion signal to the OS.
@pragma('vm:entry-point')
void groupSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final newTasks = await GroupSyncService.instance.syncFromBackground();

      if (newTasks.isNotEmpty) {
        // Post one local notification per new shared task. The plugin is
        // lazily initialized per isolate and Android 13+ permission is probed
        // before posting, keeping the worker cheap and kill-safe.
        for (final newTask in newTasks) {
          await LocalNotificationService.instance.showNotification(
            title: 'New task added in ${newTask.spaceName}',
            body: '"${newTask.title}"',
          );
        }
      }

      debugPrint('Workmanager [$task]: group sync completed '
          'with ${newTasks.length} new task(s)');
      return true;
    } catch (e) {
      debugPrint('Workmanager [$task] group sync failed: $e');
      return false;
    }
  });
}

void main() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Register the Dart callback that completes tasks when a home screen
  //    widget checkbox is tapped (fires in a background isolate).
  HomeWidget.registerBackgroundCallback(backgroundCallback);

  // 3. Register the periodic background group-sync worker. Best-effort: a
  //    failure here must never block app boot, so it is guarded separately.
  try {
    await Workmanager().initialize(groupSyncCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      groupSyncTaskName,
      groupSyncTaskName,
      frequency: const Duration(hours: 1),
      // `update` keeps the existing schedule if a previous registration used a
      // different frequency, avoiding surprise re-scheduling during dev.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint("Workmanager registration failed (safe to ignore): $e");
  }

  // 4. Load preferences instantly
  final prefs = await SharedPreferences.getInstance();
  
  // 5. Boot Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // 6. AWAIT notifications so timezones and channels are fully locked in BEFORE the app loads data
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint("Notification initialization failed: $e");
  }

  //  7. CREATE STANDALONE RIVERPOD CONTAINER
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );

  // 8. PRE-WARM THE UI STATE (Prevents Layout Shift / Pop-in)
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      // A. Load user preferences instantly
      container.read(customAccentProvider.notifier).loadSettings(user.uid);
      container.read(notificationSettingsProvider.notifier).loadSettings(user.uid);
      container.read(themeModeProvider.notifier).loadSettings(user.uid);
      // A2. Cache the UID for the background sync worker so it can resolve the
      //     user even when FirebaseAuth hasn't restored its session in-isolate.
      unawaited(GroupSyncService.instance.cacheUid(user.uid));
      // B. Explicitly fetch the cloud UserModel and hydrate the local
      //    economy/stats/badge providers before the first frame, so a fresh
      //    install never renders a Trophy Room or coin balance of 0.
      final cloudModel =
          await FirestoreService.instance.getUserModel(user.uid);
      if (cloudModel != null) {
        container.read(rewardsProvider.notifier).hydrateFromCloud(cloudModel);
      }
      // C. Kick off the live coins/economy streams so the AppBar coin pill and
      //    Trophy Room already have a subscription in flight.
      container.read(coinsProvider);
      container.read(userStreamProvider);
      // D. Force Firestore to load local task cache BEFORE drawing the screen
      // We give it a tiny 500ms timeout just in case, so it never freezes the app.
      final tasks = await container.read(firestorePlannerStreamProvider.future)
          .timeout(const Duration(milliseconds: 500));
      // E. Silently evaluate the "Clean Slate" badge in the background.
      unawaited(
        container.read(rewardsProvider.notifier).evaluateCleanSlateBadge(tasks),
      );
    } catch (e) {
      debugPrint("Pre-warm timeout/error (safe to ignore): $e");
    }
  }

  // 9. Paint the app with the fully loaded state. 
  // The native splash screen drops exactly here, revealing perfect data!
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CheqApp(),
    ),
  );
}

// ── ROOT APPLICATION COMPONENT ──────────────────
class CheqApp extends ConsumerStatefulWidget {
  const CheqApp({super.key});

  @override
  ConsumerState<CheqApp> createState() => _CheqAppState();
}

class _CheqAppState extends ConsumerState<CheqApp> with WidgetsBindingObserver {
  /// True once the app has reached the foreground for the first time. The very
  /// first resume right after launch is already covered by the boot pre-warm,
  /// so it is skipped to avoid a redundant duplicate fetch.
  bool _hasResumedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    if (!_hasResumedOnce) {
      _hasResumedOnce = true;
      return;
    }

    // Foreground sync: immediately pull the latest group data from Firestore
    // so the UI updates the moment the user re-opens the app instead of
    // waiting for the next hourly background sync.
    _refreshGroupDataOnForeground();
  }

  /// Fire-and-forget foreground refresh of shared group data. Never blocks the
  /// UI and is fully offline-safe (the service swallows every failure).
  Future<void> _refreshGroupDataOnForeground() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await GroupSyncService.instance.cacheUid(uid);
      }
      ref.read(groupSyncProvider.notifier).syncNow();
    } catch (e) {
      debugPrint('Foreground group sync trigger failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final appTheme = ref.watch(appThemeProvider);

    return MaterialApp(
      title: const String.fromEnvironment('APP_NAME', defaultValue: 'Ariadne'),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: appTheme.light,
      darkTheme: appTheme.dark,
      home: const AuthGate(),
    );
  }
}