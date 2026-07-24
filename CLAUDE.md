# Project Overview
**Cheq (Flavors: Moon, Ariadne)** is a Flutter-based ToDo list and Daily Planner application. It features a real-time cloud-syncing architecture, an interactive Todoist-style daily schedule, a gamified token reward engine, Android home screen widgets, and robust local timezone-aware notifications.

## Core Tech Stack
* **Framework:** Flutter (Dart)
* **State Management:** Riverpod 3.0 (Strictly modern `Notifier` and `AsyncNotifier` patterns)
* **Backend:** Firebase (Cloud Firestore, FirebaseAuth)
* **Notifications:** `flutter_local_notifications` (with timezone support)
* **Local Storage:** `flutter_secure_storage` & `shared_preferences`
* **Native Integrations:** `home_widget` (for Android RemoteViews/Kotlin background sync)

## Target Platforms & Native Constraints
* **Primary Target:** Android (Specifically handling Android 13+ constraints).
* **Notification Permissions:** Android 13+ requires explicit runtime permission requests for notifications. Alarms rely on `USE_EXACT_ALARM` and `SCHEDULE_EXACT_ALARM`. 
* **Native Android UI:** Home screen widgets are powered by Kotlin `WidgetRemoteViewsService` and `DailyTaskWidgetProvider` communicating with Dart via `SharedPreferences`.

## Build & Run Commands
* **Fetch Dependencies:** `flutter pub get`
* **Standard Run:** `flutter run`
* **Run with Flavor/Custom Name:** `flutter run --dart-define=APP_NAME="Ariadne"`
* **Deep Clean (Used for Native/Gradle crashes):** `flutter clean && flutter pub get && flutter run`
* **Generate Launcher/Notification Icons:** `dart run flutter_launcher_icons`
* **Build Production APK:** `flutter build apk --release`

## Code Style & Architecture Rules
* **Directory Structure:** Adhere to the existing feature-first/layer-first routing:
  * `/models` - Immutable data classes with `copyWith`, `toMap`, `fromMap`.
  * `/providers` - Riverpod Notifiers and global state definitions.
  * `/screens` - Top-level Scaffold pages.
  * `/services` - Singleton wrappers for external APIs (Firebase, Notifications).
  * `/widgets` - Reusable, isolated UI components.
  * `/utils` - Algorithms (e.g., Liquid Rescheduler, AI logic).
* **State Management (Riverpod 3.0 Strict):** * NEVER use legacy `StateProvider`, `StateNotifierProvider`, or `ChangeNotifierProvider`.
  * ALWAYS use modern `NotifierProvider` and `AsyncNotifierProvider` classes.
  * Providers must be declared as global final constants.
  * State mutations must occur through explicit class methods (e.g., `ref.read(provider.notifier).updateValue()`), not by directly assigning `.state`.
* **Async & Boot Logic:**
  * Prevent UI layout shifts: Use the Deferred Boot Architecture in `auth_gate.dart`. Pre-warm data streams and await notification initialization *before* removing the loading screen.
  * Do not mutate Riverpod state directly inside a widget's `build()` method. Use `WidgetsBinding.instance.addPostFrameCallback` if a frame-dependent initialization is absolutely required.
* **Styling:** Rely on `Theme.of(context).colorScheme` (Material 3) for all colors instead of hardcoded hex values to maintain the dynamic Dark Mode / Custom Theme engines.