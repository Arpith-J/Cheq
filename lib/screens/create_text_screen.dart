import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/local_note_model.dart';
import '../providers/local_notes_provider.dart';

class CreateTextScreen extends ConsumerStatefulWidget {
  const CreateTextScreen({super.key});

  @override
  ConsumerState<CreateTextScreen> createState() => _CreateTextScreenState();
}

class _CreateTextScreenState extends ConsumerState<CreateTextScreen> {
  final _contentController = TextEditingController();
  final _titleController = TextEditingController();
  final _contentFocus = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _contentFocus.requestFocus());
  }

  @override
  void dispose() {
    _contentController.dispose();
    _titleController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _contentFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final note = LocalNoteModel(
        id: 'note_${now.millisecondsSinceEpoch}',
        createdAt: now,
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        content: content,
        type: NoteType.text,
      );

      await ref.read(localNotesProvider.notifier).addNote(note);

      if (mounted) Navigator.pop(context, note);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New Note'),
        actions: [
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Title (optional)',
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.38),
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TextField(
                controller: _contentController,
                focusNode: _contentFocus,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Start typing...',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
