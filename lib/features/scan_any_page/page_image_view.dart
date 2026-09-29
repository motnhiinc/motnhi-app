import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'scanned_page.dart';

Rect imageRect(Size view, ScannedPage page) {
  final scale = math.min(view.width / page.width, view.height / page.height);
  final width = page.width * scale;
  final height = page.height * scale;
  return Rect.fromLTWH(
    (view.width - width) / 2,
    (view.height - height) / 2,
    width,
    height,
  );
}

Rect lineRect(Rect image, ScannedLine line) => Rect.fromLTWH(
  image.left + line.left * image.width,
  image.top + line.top * image.height,
  line.width * image.width,
  line.height * image.height,
);

class PageImageView extends StatelessWidget {
  const PageImageView({
    super.key,
    required this.page,
    required this.activeLine,
  });

  final ScannedPage page;
  final ValueListenable<int> activeLine;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ValueListenableBuilder<int>(
      valueListenable: activeLine,
      builder: (context, index, _) => Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(page.jpegBytes, fit: BoxFit.contain),
          CustomPaint(painter: _PagePainter(page, index)),
        ],
      ),
    ),
  );
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.page, this.activeIndex);
  final ScannedPage page;
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = imageRect(size, page);
    if (activeIndex >= 0 && activeIndex < page.lines.length) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          lineRect(rect, page.lines[activeIndex]),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0x66FFC94A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PagePainter oldDelegate) =>
      oldDelegate.page != page || oldDelegate.activeIndex != activeIndex;
}
