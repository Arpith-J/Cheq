// lib/widgets/constellation_painter.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/star_model.dart';

/// Custom painter for the Constellation Data Core. Renders the user's
/// collected stars as glowing 4-pointed "astroid" sparkles that drift along a
/// gentle orbit, fully connected by faint constellation lines, with a subtle
/// pulse driven by [animationValue].
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.stars,
    required this.animationValue,
    this.panOffset = Offset.zero,
    this.lineColor = Colors.white,
  });

  final List<StarModel> stars;
  final double animationValue;
  final Offset panOffset;

  /// Base color of the connecting constellation lines. Derived from the
  /// surrounding theme so lines stay visible on both dark and light surfaces.
  final Color lineColor;

  /// Color per star category.
  static const Map<String, Color> categoryColors = {
    'focus': Color(0xFF00E5FF), // cyan
    'creativity': Color(0xFFFF4081), // pinkAccent
    'academic': Color(0xFFFFC107), // amber
  };

  /// Amplitude (px) of the smooth orbital drift applied to every star.
  static const double _driftAmplitude = 15.0;

  /// Maximum radius of a rendered star, scaled by the sparkle pulse.
  static const double _baseRadius = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(panOffset.dx, panOffset.dy);

    // Compute the dynamic, drifting coordinates for every star first so the
    // lines and the glowing shapes are drawn in the exact same spot.
    final points = <Offset>[];
    final colors = <Color>[];

    for (final star in stars) {
      final phase = animationValue * 2 * math.pi;
      final seed = star.id.hashCode.toDouble();

      final renderX =
          star.dx * size.width + math.sin(phase + seed) * _driftAmplitude;
      final renderY =
          star.dy * size.height + math.cos(phase + seed * 1.7) * _driftAmplitude;

      points.add(Offset(renderX, renderY));
      colors.add(categoryColors[star.category] ?? Colors.white);
    }

    // ── Constellation lines (every unique pair) ────────────────────────────
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.18)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      // Very subtle glow so the network reads as soft webbing, not hard lines.
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        canvas.drawLine(points[i], points[j], linePaint);
      }
    }

    // ── Glowing stars ──────────────────────────────────────────────────────
    for (var i = 0; i < points.length; i++) {
      final color = colors[i];
      // Offset each star's phase so they don't all twinkle in unison.
      final sparkle = 0.75 + 0.25 * math.sin(animationValue * 2 * math.pi + i);
      final radius = _baseRadius * (0.6 + 0.6 * sparkle);

      // Strong blurred halo behind the star shape.
      final starPaint = Paint()
        ..color = color.withValues(alpha: 0.55 * sparkle)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
      canvas.drawPath(_starPath(points[i], radius), starPaint);

      // Bright core that "sparkles" by scaling its radius.
      final corePaint = Paint()..color = color.withValues(alpha: 0.95);
      canvas.drawPath(_starPath(points[i], radius * 0.45), corePaint);
    }
  }

  /// Builds a 4-pointed "astroid" sparkle path centred on [center]. The concave
  /// quadratic curves carve the four cusps between the cardinal points.
  Path _starPath(Offset center, double radius) {
    return Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - radius)
      ..close();
  }

  @override
  bool shouldRepaint(ConstellationPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.lineColor != lineColor;
  }
}
