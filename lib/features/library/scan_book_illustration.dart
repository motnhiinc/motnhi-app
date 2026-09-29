import 'package:flutter/material.dart';

/// Lightweight viewfinder/book drawing from the approved Home concept.
class ScanBookIllustration extends StatelessWidget {
  const ScanBookIllustration({
    super.key,
    required this.color,
    required this.paper,
    required this.coral,
    required this.gold,
  });

  final Color color;
  final Color paper;
  final Color coral;
  final Color gold;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BookPainter(color, paper, coral, gold),
        child: const SizedBox.expand(),
      );
}

class _BookPainter extends CustomPainter {
  const _BookPainter(this.ink, this.paper, this.coral, this.gold);

  final Color ink;
  final Color paper;
  final Color coral;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / 270).clamp(0.5, 1.2);
    canvas.save();
    canvas.translate(
        (size.width - 270 * scale) / 2, (size.height - 180 * scale) / 2);
    canvas.scale(scale);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final left = Path()
      ..moveTo(64, 50)
      ..quadraticBezierTo(100, 39, 135, 56)
      ..lineTo(135, 142)
      ..quadraticBezierTo(100, 127, 64, 137)
      ..close();
    final right = Path()
      ..moveTo(135, 56)
      ..quadraticBezierTo(170, 39, 206, 50)
      ..lineTo(206, 137)
      ..quadraticBezierTo(170, 127, 135, 142)
      ..close();
    canvas.drawPath(left, Paint()..color = paper);
    canvas.drawPath(right, Paint()..color = coral.withValues(alpha: .35));
    canvas.drawPath(left, line);
    canvas.drawPath(right, line);
    for (final (x1, x2, y) in [
      (78.0, 113.0, 76.0),
      (78.0, 121.0, 89.0),
      (78.0, 115.0, 102.0),
      (153.0, 188.0, 116.0)
    ]) {
      canvas.drawLine(
          Offset(x1, y),
          Offset(x2, y),
          Paint()
            ..color = ink.withValues(alpha: .35)
            ..strokeWidth = 2.5);
    }
    final heart = Path()
      ..moveTo(177, 107)
      ..cubicTo(157, 96, 155, 79, 169, 75)
      ..cubicTo(175, 73, 179, 76, 182, 80)
      ..cubicTo(190, 68, 206, 76, 201, 90)
      ..cubicTo(198, 97, 189, 104, 177, 107);
    canvas.drawPath(heart, Paint()..color = coral);
    canvas.drawCircle(const Offset(226, 30), 14, Paint()..color = gold);
    final corners = Path()
      ..moveTo(53, 42)
      ..lineTo(34, 42)
      ..lineTo(34, 61)
      ..moveTo(217, 42)
      ..lineTo(236, 42)
      ..lineTo(236, 61)
      ..moveTo(34, 119)
      ..lineTo(34, 138)
      ..lineTo(53, 138)
      ..moveTo(236, 119)
      ..lineTo(236, 138)
      ..lineTo(217, 138);
    canvas.drawPath(
        corners,
        line
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BookPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper ||
      oldDelegate.coral != coral ||
      oldDelegate.gold != gold;
}
