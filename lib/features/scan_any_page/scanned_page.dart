import 'dart:typed_data';

class ScannedLine {
  const ScannedLine(this.text, this.left, this.top, this.width, this.height);

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  bool get isValid =>
      text.trim().isNotEmpty &&
      [left, top, width, height].every((v) => v.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      width > 0 &&
      height > 0 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;

  factory ScannedLine.fromMap(Map<Object?, Object?> map) => ScannedLine(
    map['text'] as String,
    (map['left'] as num).toDouble(),
    (map['top'] as num).toDouble(),
    (map['width'] as num).toDouble(),
    (map['height'] as num).toDouble(),
  );
}

class ScannedPage {
  const ScannedPage(this.jpegBytes, this.width, this.height, this.lines);

  final Uint8List jpegBytes;
  final int width;
  final int height;
  final List<ScannedLine> lines;

  String get joinedText => lines.map((line) => line.text).join('\n');

  factory ScannedPage.fromMap(Map<Object?, Object?> map) {
    final bytes = map['imageBytes'];
    final rawLines = map['lines'];
    if (bytes is! Uint8List ||
        bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024 ||
        map['width'] is! int ||
        map['height'] is! int ||
        rawLines is! List ||
        rawLines.isEmpty ||
        rawLines.length > 40) {
      throw const FormatException('invalid_scanned_page');
    }
    final lines = rawLines
        .map((raw) {
          if (raw is! Map) throw const FormatException('invalid_scanned_line');
          return ScannedLine.fromMap(raw);
        })
        .toList(growable: false);
    final runes = lines.fold<int>(
      0,
      (sum, line) => sum + line.text.runes.length,
    );
    final width = map['width']! as int;
    final height = map['height']! as int;
    if (width < 1 ||
        height < 1 ||
        width > 3000 ||
        height > 3000 ||
        runes > 4000 ||
        lines.any((line) => !line.isValid)) {
      throw const FormatException('invalid_scanned_page');
    }
    return ScannedPage(bytes, width, height, lines);
  }
}
