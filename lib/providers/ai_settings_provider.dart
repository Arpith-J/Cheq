// lib/providers/ai_settings_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class AISettingsState {
  final bool isCategorizerEnabled;
  final bool isReschedulerEnabled;
  final String? apiKey;

  const AISettingsState({
    this.isCategorizerEnabled = false,
    this.isReschedulerEnabled = false,
    this.apiKey,
  });

  AISettingsState copyWith({
    bool? isCategorizerEnabled,
    bool? isReschedulerEnabled,
    String? apiKey,
  }) {
    return AISettingsState(
      isCategorizerEnabled: isCategorizerEnabled ?? this.isCategorizerEnabled,
      isReschedulerEnabled: isReschedulerEnabled ?? this.isReschedulerEnabled,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

class AISettingsNotifier extends Notifier<AISettingsState> {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'user_gemini_api_key';
  static const _categorizerKey = 'ai_categorizer_enabled';
  static const _reschedulerKey = 'ai_rescheduler_enabled';

  @override
  AISettingsState build() {
    // Hydrate synchronously from SharedPreferences on cold boot so the saved
    // API key and toggles are already populated in state when the UI reads it.
    // SharedPreferences was loaded before runApp() in main(), so this is
    // effectively instant and never races the first frame.
    final prefs = ref.watch(sharedPrefsProvider);
    _syncStorage();
    return _stateFromPrefs(prefs);
  }

  AISettingsState _stateFromPrefs(SharedPreferences prefs) {
    return AISettingsState(
      apiKey: prefs.getString(_keyName),
      isCategorizerEnabled: prefs.getBool(_categorizerKey) ?? false,
      isReschedulerEnabled: prefs.getBool(_reschedulerKey) ?? false,
    );
  }

  /// Best-effort reconciliation between SharedPreferences (source of truth,
  /// reliable across cold boots / cache clears) and FlutterSecureStorage
  /// (secure mirror + legacy values from previous builds).
  Future<void> _syncStorage() async {
    try {
      final prefs = ref.read(sharedPrefsProvider);

      var key = prefs.getString(_keyName);
      if (key == null || key.isEmpty) {
        key = await _storage.read(key: _keyName);
        if (key != null && key.isNotEmpty) {
          await prefs.setString(_keyName, key);
        }
      } else {
        await _storage.write(key: _keyName, value: key);
      }

      if (prefs.getBool(_categorizerKey) == null) {
        final legacy = await _storage.read(key: _categorizerKey);
        if (legacy == 'true') {
          await prefs.setBool(_categorizerKey, true);
        }
      }

      if (prefs.getBool(_reschedulerKey) == null) {
        final legacy = await _storage.read(key: _reschedulerKey);
        if (legacy == 'true') {
          await prefs.setBool(_reschedulerKey, true);
        }
      }

      state = _stateFromPrefs(prefs);
    } catch (e) {
      debugPrint('AI settings sync failed: $e');
    }
  }

  Future<void> saveApiKey(String key) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_keyName, key);
    await _storage.write(key: _keyName, value: key);
    state = state.copyWith(apiKey: key);
  }

  /// Removes the saved key and disables both AI features, in memory and on disk.
  Future<void> clearApiKey() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(_keyName);
    await _storage.delete(key: _keyName);
    await prefs.setBool(_categorizerKey, false);
    await prefs.setBool(_reschedulerKey, false);
    await _storage.write(key: _categorizerKey, value: 'false');
    await _storage.write(key: _reschedulerKey, value: 'false');
    state = const AISettingsState(
      apiKey: null,
      isCategorizerEnabled: false,
      isReschedulerEnabled: false,
    );
  }

  /// Alias for [clearApiKey].
  Future<void> disconnect() => clearApiKey();

  Future<void> toggleCategorizer(bool enabled) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_categorizerKey, enabled);
    await _storage.write(key: _categorizerKey, value: enabled.toString());
    state = state.copyWith(isCategorizerEnabled: enabled);
  }

  Future<void> toggleRescheduler(bool enabled) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_reschedulerKey, enabled);
    await _storage.write(key: _reschedulerKey, value: enabled.toString());
    state = state.copyWith(isReschedulerEnabled: enabled);
  }

  Future<void> enableAll() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_categorizerKey, true);
    await prefs.setBool(_reschedulerKey, true);
    await _storage.write(key: _categorizerKey, value: 'true');
    await _storage.write(key: _reschedulerKey, value: 'true');
    state = state.copyWith(
      isCategorizerEnabled: true,
      isReschedulerEnabled: true,
    );
  }
}

final aiSettingsProvider = NotifierProvider<AISettingsNotifier, AISettingsState>(
  AISettingsNotifier.new,
);
