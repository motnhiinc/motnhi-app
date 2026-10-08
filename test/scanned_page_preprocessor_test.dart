import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page_preprocessor.dart';

void main() {
  ScannedPage page(List<ScannedLine> lines) =>
      ScannedPage(Uint8List.fromList([1]), 100, 200, lines);

  test(
    'removes isolated numeric header and footer, retains story and geometry',
    () {
      const body = ScannedLine('Có 13 chú thỏ.', 0.1, 0.4, 0.8, 0.05);
      final original = page([
        const ScannedLine('Trang 12', 0.4, 0.02, 0.2, 0.04),
        body,
        const ScannedLine('- 13 -', 0.45, 0.94, 0.1, 0.03),
      ]);
      final result = preprocessScannedPage(original);
      expect(result.lines, [same(body)]);
      expect(result.jpegBytes, same(original.jpegBytes));
      expect(result.width, original.width);
      expect(result.height, original.height);
    },
  );

  test('retains standalone body numbers and numbers beside story text', () {
    final original = page([
      const ScannedLine('Có bao nhiêu chú thỏ?', 0.1, 0.4, 0.8, 0.05),
      const ScannedLine('13', 0.45, 0.6, 0.1, 0.03),
      const ScannedLine('Đáp án:', 0.1, 0.93, 0.2, 0.03),
      const ScannedLine('14', 0.45, 0.93, 0.1, 0.03),
    ]);
    expect(preprocessScannedPage(original).lines, original.lines);
  });

  test('retains a number in a margin when it is part of nearby content', () {
    final original = page([
      const ScannedLine('Có bao nhiêu chú thỏ?', 0.1, 0.87, 0.8, 0.04),
      const ScannedLine('13', 0.45, 0.92, 0.1, 0.03),
    ]);
    expect(preprocessScannedPage(original).lines, original.lines);
  });

  test('a page with only a folio has no readable story', () {
    expect(
      () => preprocessScannedPage(
        page([const ScannedLine('13', 0.45, 0.94, 0.1, 0.03)]),
      ),
      throwsA(isA<ScanFailure>().having((e) => e.code, 'code', 'no_text')),
    );
  });

  test('a number-only body is retained rather than mistaken for a folio', () {
    final original = page([
      const ScannedLine('13', 0.45, 0.5, 0.1, 0.03),
    ]);
    expect(preprocessScannedPage(original).lines, original.lines);
  });
}
