import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    Future.microtask(() => _loadSettings());
    return const AISettingsState();
  }

  Future<void> _loadSettings() async {
    final key = await _storage.read(key: _keyName);
    final catEnabled = await _storage.read(key: _categorizerKey);
    final reschedEnabled = await _storage.read(key: _reschedulerKey);

    state = AISettingsState(
      apiKey: key,
      isCategorizerEnabled: catEnabled == 'true',
      isReschedulerEnabled: reschedEnabled == 'true',
    );
  }

  Future<void> saveApiKey(String key) async {
    await _storage.write(key: _keyName, value: key);
    state = state.copyWith(apiKey: key);
  }

  Future<void> clearApiKey() async {
    await _storage.delete(key: _keyName);
    await _storage.write(key: _categorizerKey, value: 'false');
    await _storage.write(key: _reschedulerKey, value: 'false');
    state = const AISettingsState(
      apiKey: null,
      isCategorizerEnabled: false,
      isReschedulerEnabled: false,
    );
  }

  Future<void> toggleCategorizer(bool enabled) async {
    await _storage.write(key: _categorizerKey, value: enabled.toString());
    state = state.copyWith(isCategorizerEnabled: enabled);
  }

  Future<void> toggleRescheduler(bool enabled) async {
    await _storage.write(key: _reschedulerKey, value: enabled.toString());
    state = state.copyWith(isReschedulerEnabled: enabled);
  }

  Future<void> enableAll() async {
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