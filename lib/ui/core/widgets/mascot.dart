import 'package:flutter/material.dart';

import '../theme.dart';

/// The "ew" mascot: one eye squeezed shut, one brow up, wavy grimace, tongue out.
/// Same geometry as the launcher icon and the native MascotView (52x52 grid).
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 40, this.face});

  final double size;
  final Color? face;

  @override
  Widget build(BuildContext context) {
    final c = context.ew;
    return CustomPaint(
      size: Size.square(size),
      painter: _MascotPainter(face: face ?? EwColors.dark.good, ink: EwColors.dark.bg, tongue: c.insta),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.face, required this.ink, required this.tongue});

  final Color face;
  final Color ink;
  final Color tongue;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 52;
    canvas.save();
    canvas.translate((size.width - 52 * s) / 2, (size.height - 52 * s) / 2);
    canvas.scale(s);

    canvas.drawCircle(const Offset(26, 26), 26, Paint()..color = face);

    final t = Path()
      ..moveTo(28, 38)
      ..quadraticBezierTo(28.5, 47, 33, 47)
      ..quadraticBezierTo(37.5, 47, 37, 38)
      ..close();
    canvas.drawPath(t, Paint()..color = tongue);

    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path()
      ..moveTo(9, 15)
      ..lineTo(19, 18.5)
      ..moveTo(11, 21)
      ..lineTo(18, 23.5)
      ..lineTo(11, 26)
      ..moveTo(31, 13)
      ..quadraticBezierTo(36.5, 8.5, 43, 12)
      ..moveTo(14, 38)
      ..quadraticBezierTo(18, 34, 22, 38)
      ..quadraticBezierTo(26, 42, 30, 38)
      ..quadraticBezierTo(34, 34, 38, 38);
    canvas.drawPath(p, stroke);
    canvas.drawCircle(const Offset(36.5, 23), 3.5, Paint()..color = ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) => old.face != face || old.tongue != tongue;
}
