import 'dart:io';

import '../ar/ar_narration_bundle.dart';
import 'tts_client.dart';

/// On-device narration for Scan Any Page: adapts [TtsFileSynthesizer] to the
/// [TtsClient] interface so the flow needs no network and no cloud consent.
///
/// The requested file name's extension is replaced with the synthesizer's
/// extension (`caf` on iOS, `wav` on Android) — iOS cannot encode MP3, and
/// asking for it there reports success with no file on disk.
final class DeviceTtsClient implements TtsClient {
  DeviceTtsClient(
    this._synthesizer, {
    required Directory Function() directory,
  }) : _directory = directory;

  static const _fileName = 'scan_any_page_narration';

  final TtsFileSynthesizer _synthesizer;
  final Directory Function() _directory;
  final Set<String> _generatedPaths = {};

  @override
  Future<File> generate(String confirmedText, {String? fileName}) async {
    final text = confirmedText.trim();
    if (text.isEmpty || text.runes.length > 4000) {
      throw const TtsGenerationFailure('invalid_text');
    }

    final name = _resolveFileName(fileName ?? _fileName);
    final file = File('${_directory().path}/$name');
    final ok = await _synthesizer.synthesizeToFile(text, file.path);
    if (!ok || !await file.exists()) {
      throw const TtsGenerationFailure('device_synthesis_failed');
    }

    _generatedPaths.add(file.path);
    return file;
  }

  String _resolveFileName(String requested) {
    final dot = requested.lastIndexOf('.');
    final stem = dot > 0 ? requested.substring(0, dot) : requested;
    return '$stem.${_synthesizer.fileExtension}';
  }

  @override
  Future<void> dispose() async {
    for (final path in _generatedPaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _generatedPaths.clear();
  }
}
