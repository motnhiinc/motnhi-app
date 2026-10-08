import 'native_scan_service.dart';
import 'scanned_page.dart';

/// Keeps story numbers; only an isolated, short folio in a margin is removed.
ScannedPage preprocessScannedPage(ScannedPage page) {
  final folio = RegExp(
    r'^(?:(?:page|trang)\s+)?[-–—]?\s*[0-9]{1,4}\s*[-–—]?$',
    caseSensitive: false,
  );
  final body = page.lines
      .where((line) {
        final center = line.top + line.height / 2;
        return !folio.hasMatch(line.text.trim()) ||
            (center > 0.1 && center < 0.9);
      })
      .toList();
  if (body.isEmpty) throw const ScanFailure('no_text');
  final lines = page.lines
      .where((line) {
        if (!folio.hasMatch(line.text.trim())) return true;
        final center = line.top + line.height / 2;
        final inMargin = center <= 0.1 || center >= 0.9;
        final isolated = body.every((other) {
          final gap = center < other.top
              ? other.top - (line.top + line.height)
              : line.top - (other.top + other.height);
          return gap >= 0.025;
        });
        return !(inMargin &&
            isolated &&
            line.width <= 0.3 &&
            line.height <= 0.06);
      })
      .toList(growable: false);
  return ScannedPage(page.jpegBytes, page.width, page.height, lines);
}
