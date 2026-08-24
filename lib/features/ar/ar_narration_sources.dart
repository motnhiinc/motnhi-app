import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'ar_narration_bundle.dart';

/// Writes device-speech clips for pages that have no real narration.
///
/// The container format is not a preference. iOS writes through
/// `AVAudioFile(forWriting:)`, which derives the format from the file
/// extension, and iOS cannot encode MP3 - asking for `.mp3` there throws inside
/// an async callback *after* the method has already replied, so Dart would see
/// success with no file on disk. Android writes WAV bytes whatever the
/// extension, so `.wav` simply keeps the file honest.
class FlutterTtsFileSynthesizer implements TtsFileSynthesizer {
  FlutterTtsFileSynthesizer(this._tts);

  final FlutterTts _tts;
  bool _ready = false;

  @override
  String get fileExtension => Platform.isIOS ? 'caf' : 'wav';

  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    try {
      if (!_ready) {
        // Without this the Android call is fire-and-forget and returns before
        // the file is written, so AR would launch against a half-written clip.
        await _tts.awaitSynthCompletion(true);
        _ready = true;
      }
      // The third argument is `isFullPath`; the default of false would drop the
      // clip in the platform's own directory, outside the validator root.
      await _tts.synthesizeToFile(text, filePath, true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class DioArAudioDownloader implements ArAudioDownloader {
  DioArAudioDownloader(this._dio);

  final Dio _dio;

  @override
  Future<List<int>> download(String url) async {
    // Signed asset URLs are absolute, which overrides the client's baseUrl.
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }
}
