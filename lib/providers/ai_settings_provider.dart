import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AISettingsState {
  final bool isAiEnabled;
  final String? apiKey;

  const AISettingsState({
    this.isAiEnabled = false,
    this.apiKey,
  });

  AISettingsState copyWith({
    bool? isAiEnabled,
    String? apiKey,
  }) {
    return AISettingsState(
      isAiEnabled: isAiEnabled ?? this.isAiEnabled,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

class AISettingsNotifier extends Notifier<AISettingsState> {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'user_gemini_api_key';
  static const _enabledName = 'ai_rescheduler_enabled';

  @override
  AISettingsState build() {
    Future.microtask(() => _loadSettings());
    return const AISettingsState();
  }

  Future<void> _loadSettings() async {
    final key = await _storage.read(key: _keyName);
    final enabledStr = await _storage.read(key: _enabledName);
    
    state = AISettingsState(
      apiKey: key,
      isAiEnabled: enabledStr == 'true',
    );
  }

  Future<void> saveApiKey(String key) async {
    await _storage.write(key: _keyName, value: key);
    state = state.copyWith(apiKey: key);
  }

  Future<void> clearApiKey() async {
    await _storage.delete(key: _keyName);
    await _storage.write(key: _enabledName, value: 'false');
    state = const AISettingsState(apiKey: null, isAiEnabled: false);
  }

  Future<void> toggleAiEnabled(bool isEnabled) async {
    await _storage.write(key: _enabledName, value: isEnabled.toString());
    state = state.copyWith(isAiEnabled: isEnabled);
  }
}

final aiSettingsProvider = NotifierProvider<AISettingsNotifier, AISettingsState>(
  AISettingsNotifier.new,
);