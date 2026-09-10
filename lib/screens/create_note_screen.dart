// lib/screens/create_note_screen.dart
// Hybrid Samsung Notes-style creation engine.
// Bottom layer: rich text editor (custom cursor interaction).
// Top layer: Scribble drawing canvas (transparent background, IgnorePointer
// managed by the NoteMode state so strokes and the keyboard never fight).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scribble/scribble.dart';

import '../models/local_note_model.dart';
import '../providers/local_notes_provider.dart';

/// The current editing surface of the hybrid note.
enum NoteMode { text, drawing }

enum _DrawingTool { pen, highlighter, eraser, lasso }

class CreateNoteScreen extends ConsumerStatefulWidget {
  const CreateNoteScreen({super.key});

  @override
  ConsumerState<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends ConsumerState<CreateNoteScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentKey = GlobalKey();
  final _contentFocus = FocusNode();
  late final ScribbleNotifier _scribble;

  NoteMode _mode = NoteMode.text;
  bool _isSaving = false;

  // ── Text formatting foundation ───────────────────────────────────────────
  String? _fontFamily;
  static const _fontSizes = [12.0, 14.0, 16.0, 18.0, 22.0, 26.0];
  int _fontSizeIndex = 2;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  Color? _textColor;

  // ── Drawing state ────────────────────────────────────────────────────────
  static const _strokeWidths = [2.0, 4.0, 8.0, 14.0];
  int _strokeWidthIndex = 1;
  static const _penColors = [
    Colors.black,
    Colors.grey,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];
  Color _selectedColor = Colors.black;
  Color _paperColor = Colors.white;
  _DrawingTool _activeTool = _DrawingTool.pen;
  static const _highlightColor = Color(0x66FFEB3B);
  static const _highlightWidth = 18.0;

  // Cursor interaction capture points (global coords, resolved against the
  // RenderEditable below via an overlay hit-target that wins the arena).
  Offset _lastTapGlobal = Offset.zero;
  Offset _lastDoubleTapGlobal = Offset.zero;

  bool get _paperIsLight => _paperColor.computeLuminance() > 0.5;

  Color get _effectiveTextColor =>
      _textColor ?? (_paperIsLight ? const Color(0xFF202124) : Colors.white);

  double get _fontSize => _fontSizes[_fontSizeIndex];

  @override
  void initState() {
    super.initState();
    _scribble = ScribbleNotifier();
    WidgetsBinding.instance.addPostFrameCallback((_) => _contentFocus.requestFocus());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    _scribble.dispose();
    super.dispose();
  }

  // ── Mode switching ───────────────────────────────────────────────────────

  void _switchToDrawing() {
    _contentFocus.unfocus();
    setState(() => _mode = NoteMode.drawing);
  }

  void _switchToText() {
    if (_activeTool != _DrawingTool.pen) _selectPen();
    setState(() => _mode = NoteMode.text);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _contentFocus.requestFocus());
  }

  // ── Custom cursor interaction (Samsung-style tap semantics) ──────────────

  RenderEditable? get _editable =>
      _contentKey.currentContext?.findRenderObject() as RenderEditable?;

  /// Single tap: place the cursor at the far-left start of the tapped line.
  void _placeCursorAtLineStart() {
    _placeCursorAt(_lastTapGlobal, lineStart: true);
  }

  /// Double tap: place the cursor at the exact character offset that was hit.
  void _placeCursorExactly() {
    _placeCursorAt(_lastDoubleTapGlobal, lineStart: false);
  }

  void _placeCursorAt(Offset globalPosition, {required bool lineStart}) {
    final editable = _editable;
    if (editable == null) return;

    final position = editable.getPositionForPoint(globalPosition);
    final target = lineStart
        ? editable.getLineAtOffset(position).start
        : position.offset;

    _contentFocus.requestFocus();
    _contentController.selection = TextSelection(
      baseOffset: target,
      extentOffset: target,
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<Uint8List> _renderCanvasWithPaper() async {
    final rawBytes = (await _scribble.renderImage(pixelRatio: 2.0)).buffer.asUint8List();

    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
      ui.Paint()..color = _paperColor,
    );
    canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());

    final composed =
        await recorder.endRecording().toImage(frame.image.width, frame.image.height);
    final byteData = await composed.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      return rawBytes;
    }
    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> _compressToJpeg(Uint8List rawPng) async {
    final compressed = await FlutterImageCompress.compressWithList(
      rawPng,
      minWidth: 1080,
      minHeight: 1920,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    return compressed.isNotEmpty ? compressed : rawPng;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final title = _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim();

      if (_mode == NoteMode.drawing) {
        final rawBytes = await _renderCanvasWithPaper();
        final compressedBytes = await _compressToJpeg(rawBytes);

        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/drawing_${now.millisecondsSinceEpoch}.jpg';
        await File(filePath).writeAsBytes(compressedBytes, flush: true);

        final note = LocalNoteModel(
          id: 'note_${now.millisecondsSinceEpoch}',
          createdAt: now,
          title: title,
          content: 'Drawing',
          filePath: filePath,
          type: NoteType.drawing,
        );
        await ref.read(localNotesProvider.notifier).addNote(note);
        if (mounted) Navigator.pop(context, note);
      } else {
        final content = _contentController.text.trim();
        if (content.isEmpty) {
          _contentFocus.requestFocus();
          return;
        }
        final note = LocalNoteModel(
          id: 'note_${now.millisecondsSinceEpoch}',
          createdAt: now,
          title: title,
          content: content,
          type: NoteType.text,
        );
        await ref.read(localNotesProvider.notifier).addNote(note);
        if (mounted) Navigator.pop(context, note);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Text toolbar actions ─────────────────────────────────────────────────

  void _cycleFontSize() {
    setState(() => _fontSizeIndex = (_fontSizeIndex + 1) % _fontSizes.length);
  }

  void _showFontChooser() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Font',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            for (final option in const [
              ('Default', null),
              ('Serif', 'serif'),
              ('Sans-Serif', 'sans-serif'),
              ('Monospace', 'monospace'),
              ('Cursive', 'cursive'),
            ])
              ListTile(
                title: Text(option.$1),
                trailing: _fontFamily == option.$2
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() => _fontFamily = option.$2);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showTextColorPicker() {
    Color pickerColor = _effectiveTextColor;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Text color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) => setDialogState(() => pickerColor = color),
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _textColor = null);
                Navigator.pop(dialogContext);
              },
              child: const Text('Auto'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _textColor = pickerColor);
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Drawing toolbar actions ──────────────────────────────────────────────

  void _selectPen() {
    setState(() => _activeTool = _DrawingTool.pen);
    _scribble.setColor(_selectedColor);
    _scribble.setStrokeWidth(_strokeWidths[_strokeWidthIndex]);
  }

  void _selectHighlighter() {
    setState(() => _activeTool = _DrawingTool.highlighter);
    _scribble.setColor(_highlightColor);
    _scribble.setStrokeWidth(_highlightWidth);
  }

  void _selectEraser() {
    if (_activeTool == _DrawingTool.eraser) {
      _selectPen();
      return;
    }
    setState(() => _activeTool = _DrawingTool.eraser);
    _scribble.setEraser();
  }

  void _selectLasso() {
    setState(() => _activeTool = _DrawingTool.lasso);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Lasso selection arrives in the next upgrade'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  void _openPenConfigDialog() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final cs = Theme.of(sheetContext).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pen',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Text('Thickness',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(_strokeWidths.length, (i) {
                      final w = _strokeWidths[i];
                      final isSelected = i == _strokeWidthIndex;
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() => _strokeWidthIndex = i);
                          _scribble.setStrokeWidth(w);
                        },
                        child: Container(
                          width: 40,
                          height: 36,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? cs.primaryContainer : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? cs.primary
                                  : cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: w * 2,
                              height: w * 2,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  Text('Color',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final c in _penColors)
                        GestureDetector(
                          onTap: () {
                            setSheetState(() => _selectedColor = c);
                            _scribble.setColor(c);
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.toARGB32() == _selectedColor.toARGB32()
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.4),
                                width: c.toARGB32() == _selectedColor.toARGB32() ? 3 : 1,
                              ),
                            ),
                            child: c.toARGB32() == _selectedColor.toARGB32()
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _showCustomPenColor(sheetContext),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(colors: [
                              Colors.red,
                              Colors.yellow,
                              Colors.green,
                              Colors.cyan,
                              Colors.blue,
                              Colors.purple,
                              Colors.red,
                            ]),
                          ),
                          child: const Icon(Icons.colorize,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCustomPenColor(BuildContext sheetContext) {
    Color pickerColor = _selectedColor;
    showDialog(
      context: sheetContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Custom pen color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) => setDialogState(() => pickerColor = color),
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _selectedColor = pickerColor);
                _scribble.setColor(pickerColor);
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaperColorPicker() {
    Color pickerColor = _paperColor;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Background color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) => setDialogState(() => pickerColor = color),
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _paperColor = pickerColor);
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Builders ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _paperColor,
      appBar: AppBar(
        backgroundColor: _paperColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_mode == NoteMode.text ? 'New Note' : 'New Drawing'),
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
      body: Stack(
        children: [
          _buildNoteLayer(cs),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _mode == NoteMode.text,
              child: Scribble(notifier: _scribble),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildToolbar(),
    );
  }

  Widget _buildNoteLayer(ColorScheme cs) {
    final textColor = _effectiveTextColor;
    final hintColor = textColor.withValues(alpha: 0.35);

    return Container(
      color: _paperColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontFamily: _fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Title (optional)',
                hintStyle: TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  TextField(
                    key: _contentKey,
                    controller: _contentController,
                    focusNode: _contentFocus,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: _fontFamily,
                      fontSize: _fontSize,
                      fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
                      fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
                      decoration: _underline ? TextDecoration.underline : TextDecoration.none,
                      color: textColor,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Start typing...',
                      hintStyle: TextStyle(
                        color: hintColor,
                        fontSize: _fontSize,
                        fontStyle: FontStyle.italic,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  // Gesture overlay: sits on top of the field so it wins the
                  // gesture arena, letting us implement Samsung-style tap
                  // semantics without fighting EditableText's recognizers.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _lastTapGlobal = details.globalPosition,
                      onTap: _placeCursorAtLineStart,
                      onDoubleTapDown: (details) =>
                          _lastDoubleTapGlobal = details.globalPosition,
                      onDoubleTap: _placeCursorExactly,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final cs = Theme.of(context).colorScheme;
    return BottomAppBar(
      height: 64,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _mode == NoteMode.text
              ? _buildTextToolbar(cs)
              : _buildDrawingToolbar(cs),
        ),
      ),
    );
  }

  List<Widget> _buildTextToolbar(ColorScheme cs) {
    return [
      _toolbarButton(
        cs,
        icon: Icons.draw_rounded,
        tooltip: 'Drawing canvas',
        onTap: _switchToDrawing,
      ),
      _toolbarButton(
        cs,
        icon: Icons.font_download_rounded,
        tooltip: 'Font',
        onTap: _showFontChooser,
        selected: _fontFamily != null,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_size_rounded,
        tooltip: 'Font size',
        onTap: _cycleFontSize,
        label: '${_fontSize.round()}',
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_bold_rounded,
        tooltip: 'Bold',
        onTap: () => setState(() => _bold = !_bold),
        selected: _bold,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_italic_rounded,
        tooltip: 'Italics',
        onTap: () => setState(() => _italic = !_italic),
        selected: _italic,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_underline_rounded,
        tooltip: 'Underline',
        onTap: () => setState(() => _underline = !_underline),
        selected: _underline,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_color_text_rounded,
        tooltip: 'Text color',
        onTap: _showTextColorPicker,
        selected: _textColor != null,
      ),
      const SizedBox(width: 24),
    ];
  }

  List<Widget> _buildDrawingToolbar(ColorScheme cs) {
    return [
      _toolbarButton(
        cs,
        icon: Icons.keyboard_alt_rounded,
        tooltip: 'Keyboard',
        onTap: _switchToText,
      ),
      ValueListenableBuilder<ScribbleState>(
        valueListenable: _scribble,
        builder: (context, state, _) => Row(
          children: [
            _toolbarButton(
              cs,
              icon: Icons.undo_rounded,
              tooltip: 'Undo',
              onTap: _scribble.undo,
              enabled: state.sketch.lines.isNotEmpty,
            ),
            _toolbarButton(
              cs,
              icon: Icons.redo_rounded,
              tooltip: 'Redo',
              onTap: _scribble.redo,
              enabled: _canRedo(),
            ),
          ],
        ),
      ),
      GestureDetector(
        onTap: _selectPen,
        onDoubleTap: _openPenConfigDialog,
        child: _toolbarButton(
          cs,
          icon: Icons.edit_rounded,
          tooltip: 'Pen (double-tap for style)',
          selected: _activeTool == _DrawingTool.pen,
        ),
      ),
      SizedBox(
        height: 40,
        width: 56,
        child: Center(
          child: Container(
            width: _strokeWidths[_strokeWidthIndex] * 2,
            height: _strokeWidths[_strokeWidthIndex] * 2,
            decoration: BoxDecoration(
              color: _selectedColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      _toolbarButton(
        cs,
        icon: Icons.border_color_rounded,
        tooltip: 'Highlighter',
        onTap: _selectHighlighter,
        selected: _activeTool == _DrawingTool.highlighter,
      ),
      _toolbarButton(
        cs,
        icon: Icons.auto_fix_normal_rounded,
        tooltip: 'Eraser',
        onTap: _selectEraser,
        selected: _activeTool == _DrawingTool.eraser,
      ),
      _toolbarButton(
        cs,
        icon: Icons.highlight_alt_rounded,
        tooltip: 'Lasso select',
        onTap: _selectLasso,
        selected: _activeTool == _DrawingTool.lasso,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_color_fill_rounded,
        tooltip: 'Background color',
        onTap: _showPaperColorPicker,
        selected: true,
      ),
      const SizedBox(width: 24),
    ];
  }

  bool _canRedo() {
    // The ScribbleNotifier wraps HistoryValueNotifierMixin; the redo queue is
    // populated whenever new strokes are committed in drawing mode, so this
    // simply reflects that history is available.
    return _scribble.canRedo;
  }

  Widget _toolbarButton(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool selected = false,
    bool enabled = true,
    String? label,
  }) {
    final foreground = !enabled
        ? cs.onSurface.withValues(alpha: 0.25)
        : selected
            ? cs.onPrimaryContainer
            : cs.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        onPressed: enabled ? onTap : null,
        tooltip: tooltip,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: foreground, size: 22),
            if (label != null)
              Positioned(
                right: -10,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
        style: IconButton.styleFrom(
          backgroundColor: selected && enabled
              ? cs.primaryContainer
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}