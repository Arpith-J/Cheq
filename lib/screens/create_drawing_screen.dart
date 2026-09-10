import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scribble/scribble.dart';

import '../models/local_note_model.dart';
import '../providers/local_notes_provider.dart';

class CreateDrawingScreen extends ConsumerStatefulWidget {
  const CreateDrawingScreen({super.key});

  @override
  ConsumerState<CreateDrawingScreen> createState() =>
      _CreateDrawingScreenState();
}

class _CreateDrawingScreenState extends ConsumerState<CreateDrawingScreen> {
  late final ScribbleNotifier _notifier;
  bool _isSaving = false;

  // Stroke width options
  static const _strokeWidths = [2.0, 4.0, 8.0, 14.0];
  int _selectedWidthIndex = 1;

  // Color palette
  static const _colors = [
    Colors.black,
    Colors.grey,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.brown,
  ];
  Color _selectedColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _notifier = ScribbleNotifier();
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  Future<Uint8List> _renderCanvas() async {
    final data = await _notifier.renderImage(pixelRatio: 2.0);
    return data.buffer.asUint8List();
  }

  Future<Uint8List> _compressToJpeg(Uint8List rawPng) async {
    final compressed = await FlutterImageCompress.compressWithList(
      rawPng,
      minWidth: 1080,
      minHeight: 1920,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    // Fallback: if compression returned empty list, use the raw PNG
    return compressed.isNotEmpty ? compressed : rawPng;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final rawBytes = await _renderCanvas();

      final compressedBytes = await _compressToJpeg(rawBytes);

      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final filePath = '${dir.path}/drawing_${now.millisecondsSinceEpoch}.jpg';
      await File(filePath).writeAsBytes(compressedBytes, flush: true);

      final note = LocalNoteModel(
        id: 'note_${now.millisecondsSinceEpoch}',
        createdAt: now,
        title: null,
        content: 'Drawing',
        filePath: filePath,
        type: NoteType.drawing,
      );

      await ref.read(localNotesProvider.notifier).addNote(note);

      if (mounted) Navigator.pop(context, note);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New Drawing'),
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
      body: Column(
        children: [
          // ── Toolbar ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Column(
              children: [
                // Row 1: Undo / Clear + Stroke width
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, size: 22),
                      tooltip: 'Undo',
                      onPressed: _notifier.undo,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 22),
                      tooltip: 'Clear',
                      onPressed: _notifier.clear,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.line_weight_rounded, size: 18),
                    const SizedBox(width: 4),
                    ...List.generate(_strokeWidths.length, (i) {
                      final w = _strokeWidths[i];
                      final isSelected = i == _selectedWidthIndex;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedWidthIndex = i);
                          _notifier.setStrokeWidth(w);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cs.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Container(
                              width: w * 2,
                              height: w * 2,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cs.onPrimaryContainer
                                    : cs.onSurface,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 6),
                // Row 2: Color palette
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _colors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final c = _colors[i];
                      final isSelected = c.value == _selectedColor.value;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedColor = c);
                          _notifier.setColor(c);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: cs.primary, width: 3)
                                : Border.all(
                                    color: cs.outlineVariant
                                        .withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Canvas ───────────────────────────────────────────────────
          Expanded(
            child: Container(
              color: Colors.white,
              child: Scribble(
                notifier: _notifier,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
