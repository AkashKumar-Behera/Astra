import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/astra_theme.dart';

/// A pure geometric, minimalist cosmic shape logo for Astra (No raster text, pure vector math).
class AstraLogo extends StatefulWidget {
  final double size;
  final bool animate;
  final bool showGlow;

  const AstraLogo({
    super.key,
    this.size = 96.0,
    this.animate = true,
    this.showGlow = true,
  });

  @override
  State<AstraLogo> createState() => _AstraLogoState();
}

class _AstraLogoState extends State<AstraLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AstraLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _AstraLogoPainter(
            pulse: 0.5,
            showGlow: widget.showGlow,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _AstraLogoPainter(
              pulse: _controller.value,
              showGlow: widget.showGlow,
            ),
          ),
        );
      },
    );
  }
}

class _AstraLogoPainter extends CustomPainter {
  final double pulse;
  final bool showGlow;

  _AstraLogoPainter({
    required this.pulse,
    required this.showGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Ambient Background Glow (Multi-layered Radial Blur)
    if (showGlow) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AstraTheme.primary.withValues(alpha: 0.35 + (pulse * 0.15)),
            AstraTheme.secondary.withValues(alpha: 0.15 + (pulse * 0.08)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.35));
      canvas.drawCircle(center, radius * 1.35, glowPaint);
    }

    // 2. Outer Elliptical Orbital Ring (Tilted at 35 degrees)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi * 0.18 + (pulse * 0.05));

    final orbitRect = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 1.70,
      height: radius * 0.65,
    );

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.024
      ..shader = const SweepGradient(
        colors: [
          Color(0x008B5CF6),
          Color(0xFF8B5CF6),
          Color(0xFF38BDF8),
          Color(0x0038BDF8),
        ],
        stops: [0.0, 0.45, 0.70, 1.0],
      ).createShader(orbitRect);

    canvas.drawOval(orbitRect, orbitPaint);

    // Orbital satellite spark
    final sparkPaint = Paint()
      ..color = const Color(0xFFE0E7FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);
    canvas.drawCircle(
      Offset(radius * 0.85 * math.cos(pulse * math.pi * 2), radius * 0.325 * math.sin(pulse * math.pi * 2)),
      size.width * 0.028,
      sparkPaint,
    );

    canvas.restore();

    // 3. Central Celestial Star Nexus (4-Point Curved Star Geometry)
    final starPath = Path();
    final outerR = radius * 0.76;
    final innerR = radius * 0.22;

    // Draw 4-point concave cosmic star
    starPath.moveTo(center.dx, center.dy - outerR);
    starPath.quadraticBezierTo(center.dx + innerR * 0.6, center.dy - innerR * 0.6, center.dx + outerR, center.dy);
    starPath.quadraticBezierTo(center.dx + innerR * 0.6, center.dy + innerR * 0.6, center.dx, center.dy + outerR);
    starPath.quadraticBezierTo(center.dx - innerR * 0.6, center.dy + innerR * 0.6, center.dx - outerR, center.dy);
    starPath.quadraticBezierTo(center.dx - innerR * 0.6, center.dy - innerR * 0.6, center.dx, center.dy - outerR);
    starPath.close();

    // Star Body Gradient Fill
    final starGradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFDDD6FE), // Bright Violet-White at top
          AstraTheme.primaryLight,
          AstraTheme.primary,
          AstraTheme.secondary,
        ],
        stops: const [0.0, 0.28, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerR));

    // Outer Star Drop Shadow
    canvas.drawShadow(starPath, AstraTheme.primary.withValues(alpha: 0.65), 8.0, true);
    canvas.drawPath(starPath, starGradientPaint);

    // 4. Star Inner Diamond Prism Facet
    final innerDiamondPath = Path()
      ..moveTo(center.dx, center.dy - outerR * 0.45)
      ..lineTo(center.dx + outerR * 0.45, center.dy)
      ..lineTo(center.dx, center.dy + outerR * 0.45)
      ..lineTo(center.dx - outerR * 0.45, center.dy)
      ..close();

    final innerDiamondPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.75),
          const Color(0xFFA78BFA).withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerR * 0.45));

    canvas.drawPath(innerDiamondPath, innerDiamondPaint);

    // 5. Central Glowing Luminous Core Pulsar
    final coreGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          const Color(0xFFDDD6FE).withValues(alpha: 0.9),
          AstraTheme.accentCyan.withValues(alpha: 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: innerR * (0.9 + pulse * 0.3)));

    canvas.drawCircle(center, innerR * (0.9 + pulse * 0.3), coreGlowPaint);
    canvas.drawCircle(center, innerR * 0.35, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _AstraLogoPainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.showGlow != showGlow;
  }
}
