// lib/widgets/snow_painter.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Number of flakes rendered per frame.
const int _flakeCount = 45;

/// Precomputed, deterministic flake parameters so every frame stays cheap and
/// stable (no per-frame Random allocations or flicker).
final List<_Flake> _flakes = _buildFlakes();

List<_Flake> _buildFlakes() {
  final rnd = math.Random(7);
  return List.generate(_flakeCount, (_) {
    return _Flake(
      x: rnd.nextDouble(),
      phase: rnd.nextDouble(),
      swayPhase: rnd.nextDouble() * 2 * math.pi,
      speed: 0.2 + rnd.nextDouble() * 1.4,
      sway: 6 + rnd.nextDouble() * 10,
      radius: 1.2 + rnd.nextDouble() * 2.0,
    );
  });
}

/// Continuous, dependency-free falling snow overlay for the Winter quadrant.
class SnowWeatherOverlay extends StatefulWidget {
  const SnowWeatherOverlay({super.key});

  @override
  State<SnowWeatherOverlay> createState() => _SnowWeatherOverlayState();
}

class _SnowWeatherOverlayState extends State<SnowWeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
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
        painter: _SnowPainter(_controller.value),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints ~45 small, semi-transparent flakes drifting downward with a gentle
/// sinusoidal sway for a cinematic fall.
class _SnowPainter extends CustomPainter {
  _SnowPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()..color = Colors.white.withValues(alpha: 0.8);
    final width = size.width;
    final height = size.height;

    for (final flake in _flakes) {
      // Seamless vertical loop: each flake falls from just above the top edge
      // to just below the bottom edge over one full animation cycle.
      final frac = (value + flake.phase) % 1.0;
      final travel = height * (1.0 + 0.10 * flake.speed);
      final y = frac * travel - flake.radius;

      final sway =
          math.sin((value + flake.swayPhase) * 2 * math.pi) * flake.sway;
      final x = flake.x * width + sway;

      canvas.drawCircle(Offset(x, y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter oldDelegate) => oldDelegate.value != value;
}

class _Flake {
  const _Flake({
    required this.x,
    required this.phase,
    required this.swayPhase,
    required this.speed,
    required this.sway,
    required this.radius,
  });

  /// Horizontal spawn position as a fraction of the canvas width.
  final double x;

  /// Vertical start offset (0..1) so flakes are spread out mid-fall.
  final double phase;

  /// Shifts the sine sway so flakes do not sway in unison.
  final double swayPhase;

  /// Multiplier applied to the travel distance for subtle fall-speed variety.
  final double speed;

  /// Peak horizontal displacement of the sway, in logical pixels.
  final double sway;

  /// Flake radius, in logical pixels.
  final double radius;
}
