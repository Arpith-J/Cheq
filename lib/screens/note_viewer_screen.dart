import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/local_note_model.dart';
import '../providers/local_notes_provider.dart';

class NoteViewerScreen extends ConsumerStatefulWidget {
  const NoteViewerScreen({super.key, required this.note});
  final LocalNoteModel note;

  @override
  ConsumerState<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends ConsumerState<NoteViewerScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _contentFocus;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title ?? '');
    _contentController = TextEditingController(text: widget.note.content);
    _contentFocus = FocusNode();
    _isEditing = widget.note.type == NoteType.text;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _saveEdits() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final updated = widget.note.copyWith(
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        content: content,
      );
      await ref.read(localNotesProvider.notifier).updateNote(updated);
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          'Delete "${widget.note.title ?? 'Untitled note'}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(localNotesProvider.notifier)
          .removeNote(widget.note.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDrawing = widget.note.type == NoteType.drawing;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isDrawing ? 'Drawing' : (_titleController.text.isEmpty
              ? 'Note'
              : _titleController.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, size: 22),
            tooltip: 'Share',
            onPressed: () {
              if (isDrawing && widget.note.filePath != null) {
                Share.shareXFiles([XFile(widget.note.filePath!)]);
              } else {
                Share.share(widget.note.content);
              }
            },
          ),
          if (!isDrawing) ...[
            if (_isEditing)
              FilledButton(
                onPressed: _isSaving ? null : _saveEdits,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              )
            else
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 22),
                tooltip: 'Edit',
                onPressed: () => setState(() {
                  _isEditing = true;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _contentFocus.requestFocus(),
                  );
                }),
              ),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 22),
            tooltip: 'Delete',
            onPressed: _confirmDelete,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isDrawing ? _buildDrawingView() : _buildTextView(theme, cs),
    );
  }

  Widget _buildDrawingView() {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder(
      future: ref.read(localNotesProvider.notifier).readDrawingBytes(widget.note),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_rounded,
                    size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  'Drawing not found',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextView(ThemeData theme, ColorScheme cs) {
    if (_isEditing) {
      return Padding(
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
      );
    }

    // Read-only view mode
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.note.title != null && widget.note.title!.isNotEmpty) ...[
            Text(
              widget.note.title!,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            widget.note.content,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Created ${_formatDate(widget.note.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
