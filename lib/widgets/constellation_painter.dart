// lib/widgets/constellation_painter.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/star_model.dart';

/// Custom painter for the Constellation Data Core. Renders the user's
/// collected stars as glowing orbs connected by faint constellation lines,
/// with a subtle sparkle driven by [animationValue].
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.stars,
    required this.animationValue,
    this.panOffset = Offset.zero,
  });

  final List<StarModel> stars;
  final double animationValue;
  final Offset panOffset;

  /// Color per star category.
  static const Map<String, Color> categoryColors = {
    'focus': Color(0xFF00E5FF), // cyan
    'creativity': Color(0xFFFF4081), // pinkAccent
    'academic': Color(0xFFFFC107), // amber
  };

  /// Stars closer than this many pixels get connected by a faint line.
  static const double _connectionDistance = 150.0;
  static const double _baseRadius = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(panOffset.dx, panOffset.dy);

    final points = <Offset>[];
    final colors = <Color>[];

    for (final star in stars) {
      points.add(Offset(star.dx * size.width, star.dy * size.height));
      colors.add(categoryColors[star.category] ?? Colors.white);
    }

    // ── Constellation lines ────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[i].dx - points[j].dx;
        final dy = points[i].dy - points[j].dy;
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance < _connectionDistance) {
          canvas.drawLine(points[i], points[j], linePaint);
        }
      }
    }

    // ── Glowing stars ──────────────────────────────────────────────────────
    for (var i = 0; i < points.length; i++) {
      final color = colors[i];
      // Offset each star's phase so they don't all twinkle in unison.
      final sparkle = 0.75 + 0.25 * math.sin(animationValue * 2 * math.pi + i);

      // Wide blurred halo for the glow effect.
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.6 * sparkle)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawCircle(points[i], _baseRadius * 2.4, glowPaint);

      // Bright core that "sparkles" by scaling its radius.
      final corePaint = Paint()..color = color.withValues(alpha: 0.95);
      canvas.drawCircle(points[i], _baseRadius * (0.7 + 0.5 * sparkle), corePaint);
    }
  }

  @override
  bool shouldRepaint(ConstellationPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.panOffset != panOffset;
  }
}
