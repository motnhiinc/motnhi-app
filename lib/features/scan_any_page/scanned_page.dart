import 'dart:typed_data';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

class ScannedLine {
  const ScannedLine(
    this.text,
    this.left,
    this.top,
    this.width,
    this.height, {
    this.confidence,
    this.recognizedLanguage,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  final double? confidence;
  final String? recognizedLanguage;

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
    confidence: (map['confidence'] as num?)?.toDouble(),
    recognizedLanguage: map['recognizedLanguage'] as String?,
  );
}

class ScannedPage {
  const ScannedPage(
    this.jpegBytes,
    this.width,
    this.height,
    this.lines, {
    this.quality,
    this.nativeProcessingMs = 0,
    this.diagnostics = const {},
  });

  final Uint8List jpegBytes;
  final int width;
  final int height;
  final List<ScannedLine> lines;
  final Map<String, dynamic>? quality;
  final int nativeProcessingMs;
  final Map<String, dynamic> diagnostics;

  ScannedPage normalized() => ScannedPage(
    jpegBytes,
    width,
    height,
    [
      for (final line in lines)
        ScannedLine(
          unicode.nfc(line.text),
          line.left,
          line.top,
          line.width,
          line.height,
          confidence: line.confidence,
          recognizedLanguage: line.recognizedLanguage,
        ),
    ],
    quality: quality,
    nativeProcessingMs: nativeProcessingMs,
    diagnostics: diagnostics,
  );

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
    return ScannedPage(
      bytes,
      width,
      height,
      lines,
      nativeProcessingMs: (map['nativeProcessingMs'] as num?)?.toInt() ?? 0,
      diagnostics: map['diagnostics'] is Map
          ? Map<String, dynamic>.from(map['diagnostics'] as Map)
          : const {},
      quality: map['quality'] is Map
          ? Map<String, dynamic>.from(map['quality'] as Map)
          : null,
    );
  }
}
