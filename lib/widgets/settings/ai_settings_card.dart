import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ai_settings_provider.dart';
import '../../services/gemini_api_service.dart';

class AiSettingsCard extends ConsumerWidget {
  const AiSettingsCard({super.key});

  void _showApiTutorialSheet(BuildContext context, WidgetRef ref) {
    final keyController = TextEditingController();
    final isSaving = ValueNotifier<bool>(false);
    final errorText = ValueNotifier<String?>(null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: ValueListenableBuilder<bool>(
            valueListenable: isSaving,
            builder: (_, saving, _) {
              return ValueListenableBuilder<String?>(
                valueListenable: errorText,
                builder: (_, error, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: Theme.of(context).colorScheme.primary,
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
                        controller: keyController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Paste Gemini API Key',
                          hintText: 'AIza...',
                          errorText: error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Paste',
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                keyController.text = data!.text!.trim();
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final key = keyController.text.trim();
                                        if (key.isEmpty) {
                                          errorText.value = 'Please paste your Gemini API key.';
                                          return;
                                        }

                                        errorText.value = null;
                                        isSaving.value = true;

                                        try {
                                          await GeminiApiService.validateApiKeyOrThrow(key);

                                          await ref.read(aiSettingsProvider.notifier).saveApiKey(key);
                                          await ref.read(aiSettingsProvider.notifier).toggleAiEnabled(true);

                                          if (ctx.mounted) Navigator.pop(ctx);
                                        } on GeminiApiException catch (e) {
                                          if (e.statusCode == 400) {
                                            errorText.value =
                                                'Invalid request or unsupported model. Try creating a fresh AI Studio key.';
                                          } else if (e.statusCode == 403) {
                                            errorText.value =
                                                'Access denied. Check region support, Terms acceptance, and key/project permissions.';
                                          } else if (e.statusCode == 404) {
                                            errorText.value =
                                                'Model not found. Make sure the app is using gemini-2.5-flash, not Gemini 1.5.';
                                          } else {
                                            errorText.value = e.message;
                                          }
                                        } catch (_) {
                                          errorText.value =
                                              'Could not verify the key right now. Please try again.';
                                        } finally {
                                          isSaving.value = false;
                                        }
                                      },
                                child: saving
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
                  );
                },
              );
            },
          ),
        ),
      ),
    ).whenComplete(() {
      keyController.dispose();
      isSaving.dispose();
      errorText.dispose();
    });
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
              'AI Smart Scheduling',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Use Gemini to resolve schedule conflicts automatically.',
            ),
            secondary: Icon(
              Icons.auto_awesome,
              color: aiState.isAiEnabled ? cs.primary : cs.onSurfaceVariant,
            ),
            value: aiState.isAiEnabled,
            onChanged: (value) {
              if (value && aiState.apiKey == null) {
                _showApiTutorialSheet(context, ref);
              } else {
                ref.read(aiSettingsProvider.notifier).toggleAiEnabled(value);
              }
            },
          ),
          if (aiState.isAiEnabled && aiState.apiKey != null)
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