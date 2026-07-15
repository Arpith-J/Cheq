import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ai_settings_provider.dart';

class AiSettingsCard extends ConsumerWidget {
  const AiSettingsCard({super.key});

  void _showApiTutorialSheet(BuildContext context, WidgetRef ref) {
    final keyController = TextEditingController();
    
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
          child: Column(
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
                  Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Setup AI Scheduling',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'To keep Cheq free and completely private, the AI runs directly on your device using your own Google Gemini API key. It takes 1 minute to get one.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              
              // TUTORIAL STEPS
              _TutorialStep(
                number: '1',
                text: 'Go to aistudio.google.com and sign in with your Google account.',
              ),
              _TutorialStep(
                number: '2',
                text: 'Click the "Get API key" button on the left menu.',
              ),
              _TutorialStep(
                number: '3',
                text: 'Click "Create API key", copy it, and paste it below.',
              ),
              
              const SizedBox(height: 24),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Paste Gemini API Key',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () async {
                    if (keyController.text.trim().isNotEmpty) {
                      await ref.read(aiSettingsProvider.notifier).saveApiKey(keyController.text.trim());
                      await ref.read(aiSettingsProvider.notifier).toggleAiEnabled(true);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Save & Enable AI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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
            title: const Text('AI Smart Scheduling', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Use Gemini to resolve schedule conflicts automatically.'),
            secondary: Icon(Icons.auto_awesome, color: aiState.isAiEnabled ? cs.primary : cs.onSurfaceVariant),
            value: aiState.isAiEnabled,
            onChanged: (value) {
              if (value && aiState.apiKey == null) {
                // User turned it on but has no key -> Show tutorial!
                _showApiTutorialSheet(context, ref);
              } else {
                // User just toggled it on/off normally
                ref.read(aiSettingsProvider.notifier).toggleAiEnabled(value);
              }
            },
          ),
          // Show options to update/clear key if AI is active
          if (aiState.isAiEnabled && aiState.apiKey != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('API Key Connected', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ref.read(aiSettingsProvider.notifier).clearApiKey();
                    },
                    child: Text('Disconnect', style: TextStyle(color: cs.error, fontSize: 12)),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Small helper widget for the tutorial numbers
class _TutorialStep extends StatelessWidget {
  final String number;
  final String text;

  const _TutorialStep({required this.number, required this.text});

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