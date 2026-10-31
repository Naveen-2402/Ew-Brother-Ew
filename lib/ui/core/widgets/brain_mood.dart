import 'package:flutter/material.dart';

import '../../../domain/score.dart';

/// Brain mood icon drawn in code. Changes at 0, 50, 100 and 200 reels:
/// fresh -> getting mushy -> melting -> fried. Cross-fades between moods.
class BrainMoodIcon extends StatelessWidget {
  const BrainMoodIcon({super.key, required this.mood, this.size = 72});

  final BrainMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: CustomPaint(
        key: ValueKey(mood),
        size: Size(size, size * 0.9),
        painter: _BrainPainter(mood),
      ),
    );
  }
}

class _BrainPainter extends CustomPainter {
  _BrainPainter(this.mood);

  final BrainMood mood;

  static const _fill = {
    BrainMood.fresh: Color(0xFFF7A8C4),
    BrainMood.meh: Color(0xFFD7A6BE),
    BrainMood.melting: Color(0xFFF2A66B),
    BrainMood.fried: Color(0xFFC46A4A),
  };
  static const _fold = {
    BrainMood.fresh: Color(0xFFE07FA3),
    BrainMood.meh: Color(0xFFB98AA2),
    BrainMood.melting: Color(0xFFD9824A),
    BrainMood.fried: Color(0xFF8E4630),
  };
  static const _ink = Color(0xFF1C1524);

  @override
  void paint(Canvas canvas, Size size) {
    // Designed on a 64 x 58 grid.
    final s = (size.width / 64).clamp(0.0, size.height / 58);
    canvas.save();
    canvas.translate((size.width - 64 * s) / 2, (size.height - 58 * s) / 2);
    canvas.scale(s);

    final fill = Paint()..color = _fill[mood]!;
    final fold = Paint()
      ..color = _fold[mood]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inkFill = Paint()..color = _ink;

    if (mood == BrainMood.fried) _smoke(canvas);

    // Brain silhouette: overlapping lobes.
    final lobes = Path()
      ..addOval(Rect.fromCircle(center: const Offset(20, 24), radius: 13))
      ..addOval(Rect.fromCircle(center: const Offset(33, 18), radius: 13))
      ..addOval(Rect.fromCircle(center: const Offset(46, 24), radius: 13))
      ..addOval(Rect.fromCircle(center: const Offset(48, 36), radius: 11))
      ..addOval(Rect.fromCircle(center: const Offset(32, 38), radius: 14))
      ..addOval(Rect.fromCircle(center: const Offset(16, 36), radius: 11));
    canvas.drawPath(lobes, fill);

    if (mood == BrainMood.melting) {
      // Drips.
      final drip = Path()
        ..moveTo(20, 44)
        ..quadraticBezierTo(20, 53, 23, 53)
        ..quadraticBezierTo(26, 53, 26, 46)
        ..close()
        ..moveTo(40, 47)
        ..quadraticBezierTo(40, 56, 42.5, 56)
        ..quadraticBezierTo(45, 56, 45, 47)
        ..close();
      canvas.drawPath(drip, fill);
    }

    // Folds.
    final folds = Path()
      ..moveTo(14, 20)
      ..quadraticBezierTo(18, 15, 23, 19)
      ..moveTo(29, 11)
      ..quadraticBezierTo(33, 15, 37, 11)
      ..moveTo(43, 17)
      ..quadraticBezierTo(48, 15, 51, 20)
      ..moveTo(10, 33)
      ..quadraticBezierTo(13, 30, 16, 33)
      ..moveTo(50, 31)
      ..quadraticBezierTo(53, 34, 56, 31);
    canvas.drawPath(folds, fold);

    // Face.
    switch (mood) {
      case BrainMood.fresh:
        canvas.drawCircle(const Offset(26, 30), 2.4, inkFill);
        canvas.drawCircle(const Offset(38, 30), 2.4, inkFill);
        canvas.drawPath(
          Path()
            ..moveTo(26, 37)
            ..quadraticBezierTo(32, 43, 38, 37),
          ink,
        );
      case BrainMood.meh:
        canvas.drawPath(
          Path()
            ..moveTo(23, 30)
            ..lineTo(29, 30)
            ..moveTo(35, 30)
            ..lineTo(41, 30)
            ..moveTo(27, 39)
            ..lineTo(37, 39),
          ink,
        );
      case BrainMood.melting:
        canvas.drawCircle(const Offset(26, 31), 2.2, inkFill);
        canvas.drawCircle(const Offset(38, 31), 2.2, inkFill);
        canvas.drawPath(
          Path()
            ..moveTo(22, 26)
            ..lineTo(28, 24.5)
            ..moveTo(42, 26)
            ..lineTo(36, 24.5)
            ..moveTo(25, 40)
            ..quadraticBezierTo(28.5, 37, 32, 40)
            ..quadraticBezierTo(35.5, 43, 39, 40),
          ink,
        );
      case BrainMood.fried:
        canvas.drawPath(
          Path()
            ..moveTo(23, 27)
            ..lineTo(29, 33)
            ..moveTo(29, 27)
            ..lineTo(23, 33)
            ..moveTo(35, 27)
            ..lineTo(41, 33)
            ..moveTo(41, 27)
            ..lineTo(35, 33),
          ink,
        );
        canvas.drawOval(Rect.fromCenter(center: const Offset(32, 40), width: 7, height: 5.5), inkFill);
    }
    canvas.restore();
  }

  void _smoke(Canvas canvas) {
    final smoke = Paint()
      ..color = const Color(0xFF8C8296)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(24, 6)
        ..quadraticBezierTo(21, 3, 24, 0)
        ..moveTo(40, 6)
        ..quadraticBezierTo(43, 3, 40, 0),
      smoke,
    );
  }

  @override
  bool shouldRepaint(_BrainPainter old) => old.mood != mood;
}
