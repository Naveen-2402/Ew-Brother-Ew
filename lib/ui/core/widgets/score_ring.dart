import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// F11 daily score ring, animates to the new value in 200 ms.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 64});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    final color = score >= 70 ? c.good : (score >= 40 ? c.warn : c.bad);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: score / 100),
      duration: const Duration(milliseconds: 200),
      builder: (context, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, c.surfaceHigh),
          child: Center(
            child: Text(
              '${(v * 100).round()}',
              style: ewText(size * 0.34, 760, width: 80, color: c.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}
