// lib/screens/create_note_screen.dart
// Hybrid Samsung Notes-style creation engine.
// Bottom layer: rich text editor (custom cursor interaction).
// Top layer: Scribble drawing canvas (transparent background, IgnorePointer
// managed by the NoteMode state so strokes and the keyboard never fight).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;
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
  final _quillController = QuillController.basic();
  final _scrollController = ScrollController();
  final _editorKey = GlobalKey<EditorState>();
  final _contentFocus = FocusNode();
  late final ScribbleNotifier _scribble;

  NoteMode _mode = NoteMode.text;
  bool _isSaving = false;

  // ── Text formatting foundation ───────────────────────────────────────────
  String? _fontFamily;
  static const _fontSizes = ['12', '14', '16', '18', '22', '26'];
  int _fontSizeIndex = 2;
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

  // ── Lasso selection state ────────────────────────────────────────────────
  List<Offset> _lassoPoints = [];
  bool _isDrawingLasso = false;
  Set<int> _selectedStrokeIndices = {};
  Rect? _selectionBounds;
  Offset _lassoTranslation = Offset.zero;
  bool _isDraggingSelection = false;
  Offset? _lassoTapDown;
  Sketch? _lastObservedSketch;

  // While a selection is live, the selected strokes are temporarily removed
  // from the Scribble sketch (via a non-undoable update) so they don't render
  // at their original positions; the overlay repaints them at the translated
  // offset instead. These fields track that agreed-upon state.
  Sketch? _sketchBeforeLasso;
  bool _isSketchReduced = false;
  bool _isSettingLassoSketch = false;
  bool _lassoStaleByExternalChange = false;

  // Cursor interaction capture points (global coords, resolved against the
  // RenderEditable below via an overlay hit-target that wins the arena).
  Offset _lastTapGlobal = Offset.zero;
  Offset _lastDoubleTapGlobal = Offset.zero;

  bool get _paperIsLight => _paperColor.computeLuminance() > 0.5;

  Color get _effectiveTextColor =>
      _textColor ?? (_paperIsLight ? const Color(0xFF202124) : Colors.white);

  Style get _selectionStyle => _quillController.getSelectionStyle();

  bool get _isBold =>
      _selectionStyle.attributes.containsKey(Attribute.bold.key);
  bool get _isItalic =>
      _selectionStyle.attributes.containsKey(Attribute.italic.key);
  bool get _isUnderline =>
      _selectionStyle.attributes.containsKey(Attribute.underline.key);

  double get _fontSize => double.parse(_fontSizes[_fontSizeIndex]);

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  @override
  void initState() {
    super.initState();
    _scribble = ScribbleNotifier();
    _scribble.addListener(_onSketchChanged);
    _lastObservedSketch = _scribble.currentSketch;
    _quillController.addListener(_onEditorChanged);
    _syncToggledStyle();
    WidgetsBinding.instance.addPostFrameCallback((_) => _contentFocus.requestFocus());
  }

  /// Pushes the effective text color/size into the controller's toggled style
  /// so freshly typed characters inherit the current paper contrast.
  void _syncToggledStyle() {
    _quillController.toggledStyle = _quillController.toggledStyle.merge(
      Attribute.clone(Attribute.color, _colorToHex(_effectiveTextColor)),
    );
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  /// Drops any stale lasso selection when the underlying sketch changes
  /// externally (undo/redo/erase), so selected indices never point at the
  /// wrong strokes. Lasso-driven sketch swaps (reduce/merge/restore) are
  /// excluded via [_isSettingLassoSketch].
  void _onSketchChanged() {
    final current = _scribble.currentSketch;
    if (current != _lastObservedSketch) {
      _lastObservedSketch = current;
      if (_selectedStrokeIndices.isNotEmpty && !_isSettingLassoSketch) {
        // The sketch changed through undo/redo/erase, not through the lasso
        // engine - the pending selection is stale. Mark it so the clear step
        // keeps the (already undone) canvas instead of restoring our snapshot.
        _lassoStaleByExternalChange = true;
        _clearLassoSelection();
      }
    }
  }

  @override
  void dispose() {
    _quillController.removeListener(_onEditorChanged);
    _scribble.removeListener(_onSketchChanged);
    _titleController.dispose();
    _quillController.dispose();
    _scrollController.dispose();
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

  RenderAbstractEditor? get _editor =>
      _editorKey.currentState?.renderEditor;

  /// Single tap: place the cursor at the far-left start of the tapped line.
  void _placeCursorAtLineStart() {
    _placeCursorAt(_lastTapGlobal, lineStart: true);
  }

  /// Double tap: place the cursor at the exact character offset that was hit.
  void _placeCursorExactly() {
    _placeCursorAt(_lastDoubleTapGlobal, lineStart: false);
  }

  void _placeCursorAt(Offset globalPosition, {required bool lineStart}) {
    final editor = _editor;
    if (editor == null) return;

    final position = editor.getPositionForOffset(globalPosition);
    final target = lineStart
        ? editor.getLineAtOffset(position).baseOffset
        : position.offset;

    _contentFocus.requestFocus();
    _quillController.updateSelection(
      TextSelection.collapsed(offset: target),
      ChangeSource.local,
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
    _commitLassoTranslation();
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
        final content = _quillController.document.toPlainText().trim();
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
    _quillController.formatSelection(
      Attribute.clone(Attribute.size, _fontSizes[_fontSizeIndex]),
    );
  }

  void _toggleAttribute(Attribute attribute) {
    final enabled = _selectionStyle.attributes.containsKey(attribute.key);
    _quillController
      ..skipRequestKeyboard = !attribute.isInline
      ..formatSelection(
        enabled ? Attribute.clone(attribute, null) : attribute,
      );
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
                  _quillController.formatSelection(
                    option.$2 == null
                        ? Attribute.clone(Attribute.font, null)
                        : Attribute.clone(Attribute.font, option.$2),
                  );
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
                _quillController.formatSelection(
                  Attribute.clone(Attribute.color, null),
                );
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
                _quillController.formatSelection(
                  Attribute.clone(Attribute.color, _colorToHex(pickerColor)),
                );
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
    _commitLassoTranslation();
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
    if (_activeTool == _DrawingTool.lasso) {
      _selectPen();
      return;
    }
    _commitLassoTranslation();
    setState(() => _activeTool = _DrawingTool.lasso);
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
                _syncToggledStyle();
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Lasso selection engine ───────────────────────────────────────────────

  /// The bounding box shifted by the in-flight translation, used for hit
  /// testing and for rendering the selection frame while dragging.
  Rect? get _currentSelectionBounds =>
      _selectionBounds?.shift(_lassoTranslation);

  void _onLassoTapDown(TapDownDetails details) {
    _lassoTapDown = details.localPosition;
  }

  /// Single tap: if it lands outside the selection frame, commit the pending
  /// translation and clear the selection.
  void _onLassoTap() {
    if (_lassoTapDown == null || _selectedStrokeIndices.isEmpty) return;
    if (!(_currentSelectionBounds?.contains(_lassoTapDown!) ?? false)) {
      _commitLassoTranslation();
    }
    _lassoTapDown = null;
  }

  void _onLassoPanStart(DragStartDetails details) {
    final pos = details.localPosition;

    if (_selectedStrokeIndices.isNotEmpty) {
      if (_currentSelectionBounds?.contains(pos) ?? false) {
        _isDraggingSelection = true;
        return;
      }
      _commitLassoTranslation();
    }

    _isDrawingLasso = true;
    _lassoPoints = [pos];
    setState(() {});
  }

  void _onLassoPanUpdate(DragUpdateDetails details) {
    if (_isDraggingSelection) {
      setState(() => _lassoTranslation += details.delta);
    } else if (_isDrawingLasso) {
      setState(() => _lassoPoints.add(details.localPosition));
    }
  }

  void _onLassoPanEnd(DragEndDetails details) {
    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      setState(() {});
      return;
    }

    if (_isDrawingLasso && _lassoPoints.length > 2) {
      _selectStrokesInLasso();
    }
    _isDrawingLasso = false;
    setState(() {});
  }

  /// Closes the drawn path into a polygon and flags every stroke whose points
  /// intersect it, then hides those strokes from the Scribble canvas so the
  /// overlay can render them (translated) without a duplicate ghost.
  void _selectStrokesInLasso() {
    final lines = _scribble.currentSketch.lines;
    final selected = <int>{};

    for (var i = 0; i < lines.length; i++) {
      if (_strokeIntersectsLasso(lines[i])) {
        selected.add(i);
      }
    }

    if (selected.isEmpty) {
      _lassoPoints = [];
      _isDrawingLasso = false;
      setState(() {});
      return;
    }

    _sketchBeforeLasso = _scribble.currentSketch;

    final reducedLines = <SketchLine>[];
    for (var i = 0; i < lines.length; i++) {
      if (!selected.contains(i)) {
        reducedLines.add(lines[i]);
      }
    }

    setState(() {
      _selectedStrokeIndices = selected;
      _selectionBounds = _boundsForStrokes(lines, selected);
      _lassoPoints = [];
      _lassoTranslation = Offset.zero;
    });

    _isSettingLassoSketch = true;
    _scribble.setSketch(
      sketch: Sketch(lines: reducedLines),
      addToUndoHistory: false,
    );
    _isSettingLassoSketch = false;
    _isSketchReduced = true;
  }

  bool _strokeIntersectsLasso(SketchLine line) {
    for (final p in line.points) {
      if (_pointInLassoPolygon(Offset(p.x, p.y))) return true;
    }
    return false;
  }

  /// Ray-casting point-in-polygon test.
  bool _pointInLassoPolygon(Offset point) {
    final polygon = _lassoPoints;
    if (polygon.length < 3) return false;

    var crossings = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  Rect _boundsForStrokes(List<SketchLine> lines, Set<int> indices) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final i in indices) {
      final line = lines[i];
      for (final p in line.points) {
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
    }
    return Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);
  }

  /// Applies the pending translation to the selected strokes and rebuilds the
  /// sketch in a single undo-friendly mutation, then clears the selection.
  void _commitLassoTranslation() {
    if (_selectedStrokeIndices.isEmpty) {
      _clearLassoSelection();
      return;
    }

    final original = _sketchBeforeLasso;
    if (_lassoTranslation == Offset.zero || original == null) {
      // Nothing moved: restore the untouched sketch.
      _clearLassoSelection();
      return;
    }

    final reducedLines = _scribble.currentSketch.lines;
    final movedLines = <SketchLine>[];

    for (var i = 0; i < original.lines.length; i++) {
      if (!_selectedStrokeIndices.contains(i)) continue;
      final line = original.lines[i];
      movedLines.add(
        SketchLine(
          points: line.points
              .map(
                (p) => Point(
                  p.x + _lassoTranslation.dx,
                  p.y + _lassoTranslation.dy,
                  pressure: p.pressure,
                ),
              )
              .toList(),
          color: line.color,
          width: line.width,
        ),
      );
    }

    _isSettingLassoSketch = true;
    _scribble.setSketch(sketch: Sketch(lines: [...reducedLines, ...movedLines]));
    _isSettingLassoSketch = false;
    _isSketchReduced = false;
    _clearLassoSelection();
  }

  void _clearLassoSelection() {
    // If we temporarily removed the selected strokes, put them back (without
    // touching undo history) so the canvas matches the pre-lasso state. Skip
    // the restore when the canvas was already changed externally (undo/redo).
    if (_isSketchReduced &&
        _sketchBeforeLasso != null &&
        !_lassoStaleByExternalChange) {
      _isSettingLassoSketch = true;
      _scribble.setSketch(
        sketch: _sketchBeforeLasso!,
        addToUndoHistory: false,
      );
      _isSettingLassoSketch = false;
      _isSketchReduced = false;
    }

    _sketchBeforeLasso = null;
    _lassoPoints = [];
    _isDrawingLasso = false;
    _selectedStrokeIndices = {};
    _selectionBounds = null;
    _lassoTranslation = Offset.zero;
    _isDraggingSelection = false;
    _lassoStaleByExternalChange = false;
    if (mounted) setState(() {});
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
              ignoring:
                  _mode == NoteMode.text || _activeTool == _DrawingTool.lasso,
              child: Scribble(notifier: _scribble),
            ),
          ),
          if (_mode == NoteMode.drawing && _activeTool == _DrawingTool.lasso)
            Positioned.fill(child: _buildLassoOverlay()),
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
                  QuillEditor.basic(
                    controller: _quillController,
                    focusNode: _contentFocus,
                    scrollController: _scrollController,
                    config: QuillEditorConfig(
                      editorKey: _editorKey,
                      expands: true,
                      scrollable: true,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      placeholder: 'Start typing...',
                      enableSelectionToolbar: false,
                      scrollBottomInset: 0,
                      scrollPhysics: const ClampingScrollPhysics(),
                    ),
                  ),
                  // Gesture overlay: sits on top of the editor so it wins the
                  // gesture arena, letting us implement Samsung-style tap
                  // semantics without fighting QuillEditor's recognizers.
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

  Widget _buildLassoOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onLassoTapDown,
      onTap: _onLassoTap,
      onPanStart: _onLassoPanStart,
      onPanUpdate: _onLassoPanUpdate,
      onPanEnd: _onLassoPanEnd,
      child: CustomPaint(
        painter: _LassoPainter(
          lassoPoints: _lassoPoints,
          isDrawingLasso: _isDrawingLasso,
          selectionBounds: _selectionBounds,
          selectedStrokeIndices: _selectedStrokeIndices,
          lassoTranslation: _lassoTranslation,
          currentSketch: _scribble.currentSketch,
        ),
        size: Size.infinite,
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
        onTap: () => _toggleAttribute(Attribute.bold),
        selected: _isBold,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_italic_rounded,
        tooltip: 'Italics',
        onTap: () => _toggleAttribute(Attribute.italic),
        selected: _isItalic,
      ),
      _toolbarButton(
        cs,
        icon: Icons.format_underline_rounded,
        tooltip: 'Underline',
        onTap: () => _toggleAttribute(Attribute.underline),
        selected: _isUnderline,
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

/// Paints the lasso selection UI: the dashed selection polygon while drawing,
/// the selected (possibly translated) strokes, and the draggable bounding box.
class _LassoPainter extends CustomPainter {
  final List<Offset> lassoPoints;
  final bool isDrawingLasso;
  final Rect? selectionBounds;
  final Set<int> selectedStrokeIndices;
  final Offset lassoTranslation;
  final Sketch? currentSketch;

  _LassoPainter({
    required this.lassoPoints,
    required this.isDrawingLasso,
    this.selectionBounds,
    this.selectedStrokeIndices = const {},
    this.lassoTranslation = Offset.zero,
    this.currentSketch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintSelectedStrokes(canvas);
    _paintSelectionOverlay(canvas);
  }

  void _paintSelectedStrokes(Canvas canvas) {
    final sketch = currentSketch;
    if (sketch == null || selectedStrokeIndices.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    for (final index in selectedStrokeIndices) {
      if (index < 0 || index >= sketch.lines.length) continue;
      final line = sketch.lines[index];
      final path = _pathForLine(line);
      if (path == null) continue;
      paint.color = Color(line.color);
      canvas.drawPath(path, paint);
    }
  }

  Path? _pathForLine(SketchLine line) {
    if (line.points.isEmpty) return null;

    final simulatePressure = line.points.every(
      (p) => p.pressure == line.points.first.pressure,
    );

    final outlinePoints = pf.getStroke(
      line.points
          .map(
            (p) => pf.PointVector(
              p.x + lassoTranslation.dx,
              p.y + lassoTranslation.dy,
              p.pressure,
            ),
          )
          .toList(),
      options: pf.StrokeOptions(
        size: line.width * 2,
        simulatePressure: simulatePressure,
      ),
    );

    if (outlinePoints.isEmpty) return null;

    if (outlinePoints.length < 2) {
      return Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(outlinePoints[0].dx, outlinePoints[0].dy),
            radius: 1,
          ),
        );
    }

    final path = Path()..moveTo(outlinePoints[0].dx, outlinePoints[0].dy);
    for (var i = 1; i < outlinePoints.length - 1; i++) {
      final p0 = outlinePoints[i];
      final p1 = outlinePoints[i + 1];
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }
    return path;
  }

  void _paintSelectionOverlay(Canvas canvas) {
    if (isDrawingLasso && lassoPoints.length > 1) {
      _paintDashedPolygon(canvas);
    }

    final bounds = selectionBounds;
    if (bounds != null && selectedStrokeIndices.isNotEmpty && !isDrawingLasso) {
      _paintBoundingBox(canvas, bounds.shift(lassoTranslation));
    }
  }

  void _paintDashedPolygon(Canvas canvas) {
    final path = Path();
    path.moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
    for (var i = 1; i < lassoPoints.length; i++) {
      path.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blueAccent.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    _drawDashedPath(
      canvas,
      path,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      final total = metric.length;
      var distance = 0.0;
      while (distance < total) {
        final endOffset = (distance + dash).clamp(0.0, total);
        final start = metric.getTangentForOffset(distance)?.position;
        final end = metric.getTangentForOffset(endOffset)?.position;
        if (start != null && end != null) {
          canvas.drawLine(start, end, paint);
        }
        distance += dash + gap;
      }
    }
  }

  void _paintBoundingBox(Canvas canvas, Rect bounds) {
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.blueAccent.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
    _drawDashedPath(
      canvas,
      Path()..addRect(bounds),
      Paint()
        ..color = Colors.blueAccent.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const handle = 7.0;
    final handlePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handle, height: handle),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) {
    return oldDelegate.lassoPoints != lassoPoints ||
        oldDelegate.isDrawingLasso != isDrawingLasso ||
        oldDelegate.selectionBounds != selectionBounds ||
        oldDelegate.selectedStrokeIndices != selectedStrokeIndices ||
        oldDelegate.lassoTranslation != lassoTranslation ||
        oldDelegate.currentSketch != currentSketch;
  }
}