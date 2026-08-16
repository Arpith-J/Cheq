import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart'; // To access your existing sharedPrefsProvider

final carryOverTasksProvider = NotifierProvider<CarryOverTasksNotifier, bool>(CarryOverTasksNotifier.new);

class CarryOverTasksNotifier extends Notifier<bool> {
  static const _key = 'carry_over_pending_tasks';

  @override
  bool build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getBool(_key) ?? true; // Defaults to True
  }

  Future<void> toggle(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_key, value);
    state = value;
  }
}

final showGroupTasksProvider = NotifierProvider<ShowGroupTasksNotifier, bool>(ShowGroupTasksNotifier.new);

class ShowGroupTasksNotifier extends Notifier<bool> {
  static const _key = 'show_group_tasks_on_main';

  @override
  bool build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getBool(_key) ?? true; // Defaults to True
  }

  Future<void> toggle(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_key, value);
    state = value;
  }
}