// lib/utils/hybrid_note_exporter.dart
// Rasterizes a hybrid note (rich text + drawing canvas) by capturing the
// widget behind a RepaintBoundary and flattening it into a single high-
// resolution JPEG stored in the device cache directory for sharing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class HybridNoteExporter {
  HybridNoteExporter._();

  /// Captures the widget behind [boundaryKey] (a [RepaintBoundary] wrapping the
  /// hybrid note Stack) and writes a flattened JPEG to the cache directory.
  ///
  /// Returns the absolute path of the exported file, or `null` when the capture
  /// or the encode step fails. The caller is responsible for the tile's
  /// lifecycle; temporary cache files can be cleaned up by the OS.
  static Future<String?> exportToJpeg(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
    int quality = 90,
  }) async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) return null;

      final compressed = await FlutterImageCompress.compressWithList(
        pngBytes.buffer.asUint8List(),
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/hybrid_note_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(compressed, flush: true);
      return file.path;
    } finally {
      image.dispose();
    }
  }
}