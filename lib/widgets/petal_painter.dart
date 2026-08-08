// lib/widgets/petal_painter.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Number of petals rendered per frame.
const int _petalCount = 24;

/// Precomputed, deterministic petal parameters so every frame stays cheap and
/// stable (no per-frame Random allocations or flicker).
final List<_Petal> _petals = _buildPetals();

List<_Petal> _buildPetals() {
  final rnd = math.Random(3);
  return List.generate(_petalCount, (_) {
    return _Petal(
      x: rnd.nextDouble(),
      phase: rnd.nextDouble(),
      swayPhase: rnd.nextDouble() * 2 * math.pi,
      speed: 0.4 + rnd.nextDouble() * 1.2,
      sway: 10 + rnd.nextDouble() * 14,
      radiusX: 2.0 + rnd.nextDouble() * 2.5,
      radiusY: 1.2 + rnd.nextDouble() * 1.6,
      tilt: rnd.nextDouble() * math.pi,
      opacity: 0.55 + rnd.nextDouble() * 0.35,
    );
  });
}

/// Continuous, dependency-free drifting petal overlay for the Spring quadrant.
class PetalWeatherOverlay extends StatefulWidget {
  const PetalWeatherOverlay({super.key});

  @override
  State<PetalWeatherOverlay> createState() => _PetalWeatherOverlayState();
}

class _PetalWeatherOverlayState extends State<PetalWeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _PetalPainter(_controller.value),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints ~24 soft-pink petals drifting sideways and down while gently
/// tumbling as they fall.
class _PetalPainter extends CustomPainter {
  _PetalPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final width = size.width;
    final height = size.height;

    for (final petal in _petals) {
      // Seamless vertical loop, same trick as the snow overlay.
      final frac = (value + petal.phase) % 1.0;
      final travel = height * (1.0 + 0.12 * petal.speed);
      final y = frac * travel - petal.radiusY;

      final sway =
          math.sin((value + petal.swayPhase) * 2 * math.pi) * petal.sway;
      final x = petal.x * width + sway;

      final rotation = petal.tilt + (value + petal.phase) * math.pi * 0.5;
      final paint = Paint()
        ..color = const Color(0xFFF48FB1).withValues(alpha: petal.opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: petal.radiusX * 2,
          height: petal.radiusY * 2,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PetalPainter oldDelegate) => oldDelegate.value != value;
}

class _Petal {
  const _Petal({
    required this.x,
    required this.phase,
    required this.swayPhase,
    required this.speed,
    required this.sway,
    required this.radiusX,
    required this.radiusY,
    required this.tilt,
    required this.opacity,
  });

  /// Horizontal spawn position as a fraction of the canvas width.
  final double x;

  /// Vertical start offset (0..1) so petals are spread out mid-fall.
  final double phase;

  /// Shifts the sine sway so petals do not sway in unison.
  final double swayPhase;

  /// Multiplier applied to the travel distance for subtle fall-speed variety.
  final double speed;

  /// Peak horizontal displacement of the sway, in logical pixels.
  final double sway;

  /// Half-width of the petal ellipse, in logical pixels.
  final double radiusX;

  /// Half-height of the petal ellipse, in logical pixels.
  final double radiusY;

  /// Starting rotation of the petal.
  final double tilt;

  /// Alpha used when rendering this petal.
  final double opacity;
}
