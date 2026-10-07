import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ar/ar_narration_bundle.dart';

/// Owns native-compatible copies of a scan's validated, ordered MP3 clips.
/// Listen keeps its original files; disposal waits for pending copies.
class ScannedPageArAudio {
  ScannedPageArAudio({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? _nativeAudioDirectory;

  static Future<Directory> _nativeAudioDirectory() async {
    // path_provider uses Library/Caches on iOS, but the native reader allows
    // NSTemporaryDirectory only. Android instead requires its app cache dir.
    return Platform.isAndroid
        ? await getTemporaryDirectory()
        : Directory.systemTemp;
  }

  final Future<Directory> Function() _temporaryDirectory;
  Directory? _directory;
  Future<ArNarrationPage>? _preparation;
  Future<void>? _disposal;
  bool _disposed = false;

  Future<ArNarrationPage> prepare(List<File> clips) async {
    _ensureLive();
    try {
      return await (_preparation ??= _prepare(List.of(clips)));
    } catch (_) {
      _preparation = null;
      rethrow;
    }
  }

  Future<ArNarrationPage> _prepare(List<File> clips) async {
    if (clips.isEmpty || clips.length > 10000) {
      throw const ArNarrationFailure('audio_missing');
    }
    try {
      final root = await _temporaryDirectory();
      _ensureLive();
      _directory = await root.createTemp('scan-ar-');
      _ensureLive();
      final paths = <String>[];
      for (var i = 0; i < clips.length; i++) {
        if (!await clips[i].exists() || await clips[i].length() == 0) {
          throw const ArNarrationFailure('audio_missing');
        }
        _ensureLive();
        final name = arSegmentFileName(
          storyId: 'scan',
          pageNumber: 1,
          sortOrder: i,
          extension: 'mp3',
        );
        final copy = await clips[i].copy('${_directory!.path}/$name');
        _ensureLive();
        paths.add(copy.path);
      }
      return ArNarrationPage(
        pageId: 'scanned-page',
        pageNumber: 1,
        audioFilePaths: paths,
      );
    } catch (_) {
      await _clearDirectory();
      rethrow;
    }
  }

  void _ensureLive() {
    if (_disposed) throw const ArNarrationFailure('cancelled');
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _preparation;
    } catch (_) {
      // Failed/cancelled preparation already clears partial copies.
    }
    await _clearDirectory();
  }

  Future<void> _clearDirectory() async {
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _directory = null;
  }
}
