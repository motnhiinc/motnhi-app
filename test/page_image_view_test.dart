import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/page_image_view.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

void main() {
  final page = ScannedPage(Uint8List.fromList([0xff, 0xd8, 0xff]), 440, 585, [
    ScannedLine('line', 0.1, 0.1, 0.8, 0.2),
  ]);

  test(
    'fits portrait page inside view and maps line box within image rect',
    () {
      final image = imageRect(const Size(704, 650), page);
      expect(image.left, closeTo(107.5556, 0.01));
      expect(image.top, 0);
      expect(image.width, closeTo(488.8889, 0.01));
      expect(
        lineRect(image, page.lines.single),
        Rect.fromLTWH(
          image.left + image.width * .1,
          image.height * .1,
          image.width * .8,
          image.height * .2,
        ),
      );
    },
  );

  test('rejects boxes that overflow the normalized page', () {
    expect(ScannedLine('bad', .8, .1, .3, .2).isValid, isFalse);
  });
}
