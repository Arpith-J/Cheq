import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ai_settings_provider.dart';

class AiSettingsCard extends ConsumerWidget {
  const AiSettingsCard({super.key});

  void _showApiTutorialSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ApiKeySetupSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiSettingsProvider);
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            title: const Text(
              'AI Auto-Categorizer',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Automatically suggest categories for new tasks.',
            ),
            secondary: Icon(
              Icons.label_outline_rounded,
              color: aiState.isCategorizerEnabled ? cs.primary : cs.onSurfaceVariant,
            ),
            value: aiState.isCategorizerEnabled,
            onChanged: (value) {
              if (value && (aiState.apiKey == null || aiState.apiKey!.isEmpty)) {
                _showApiTutorialSheet(context, ref);
              } else {
                ref.read(aiSettingsProvider.notifier).toggleCategorizer(value);
              }
            },
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          SwitchListTile.adaptive(
            title: const Text(
              'AI Smart Rescheduler',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Intelligently shift tasks when conflicts occur.',
            ),
            secondary: Icon(
              Icons.schedule_rounded,
              color: aiState.isReschedulerEnabled ? cs.primary : cs.onSurfaceVariant,
            ),
            value: aiState.isReschedulerEnabled,
            onChanged: (value) {
              if (value && (aiState.apiKey == null || aiState.apiKey!.isEmpty)) {
                _showApiTutorialSheet(context, ref);
              } else {
                ref.read(aiSettingsProvider.notifier).toggleRescheduler(value);
              }
            },
          ),
          if (aiState.apiKey != null && aiState.apiKey!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'API Key Connected',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ref.read(aiSettingsProvider.notifier).clearApiKey();
                    },
                    child: Text(
                      'Disconnect',
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ApiKeySetupSheet extends ConsumerStatefulWidget {
  const _ApiKeySetupSheet();

  @override
  ConsumerState<_ApiKeySetupSheet> createState() => _ApiKeySetupSheetState();
}

class _ApiKeySetupSheetState extends ConsumerState<_ApiKeySetupSheet> {
  late final TextEditingController _keyController;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorText = 'Please paste your Gemini API key.');
      return;
    }

    setState(() {
      _errorText = null;
      _isSaving = true;
    });

    try {
      await ref.read(aiSettingsProvider.notifier).saveApiKey(key);
      await ref.read(aiSettingsProvider.notifier).enableAll();

      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Could not save the key. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Setup AI Scheduling',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'To keep Cheq private and avoid charging you indirectly, AI uses your own Google Gemini API key.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 24),
            const _TutorialStep(
              number: '1',
              text: 'Go to aistudio.google.com and sign in with your Google account.',
            ),
            const _TutorialStep(
              number: '2',
              text: 'Open API Keys and create a new Gemini API key.',
            ),
            const _TutorialStep(
              number: '3',
              text: 'Copy the key and paste it below. Cheq will test it before enabling AI.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _keyController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Paste Gemini API Key',
                hintText: 'AIza...',
                errorText: _errorText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _keyController.text = data!.text!.trim();
                    }
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your key stays on your device and is used only for your own AI requests.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _isSaving
                    ? null
                    : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text(
                        'Verify & Enable AI',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _TutorialStep extends StatelessWidget {
  final String number;
  final String text;

  const _TutorialStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(height: 1.4)),
          ),
        ],
      ),
    );
  }
}