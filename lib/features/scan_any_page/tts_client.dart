import 'dart:io';

import 'package:dio/dio.dart';

import '../../data/sources/api_client.dart';

abstract interface class TtsClient {
  Future<File> generate(String confirmedText);

  Future<void> dispose();
}

final class TtsGenerationFailure implements Exception {
  const TtsGenerationFailure(this.code);

  final String code;
}

final class HttpTtsClient implements TtsClient {
  HttpTtsClient(
    this._apiClient, {
    Directory Function()? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory ?? _systemTemporaryDirectory;

  static const _fileName = 'scan_any_page_narration.mp3';

  final ApiClient _apiClient;
  final Directory Function() _temporaryDirectory;
  File? _generatedFile;

  @override
  Future<File> generate(String confirmedText) async {
    final text = confirmedText.trim();
    if (text.isEmpty || text.length > 4000) {
      throw const TtsGenerationFailure('invalid_text');
    }

    final response = await _apiClient.send<List<int>>(
      () => _apiClient.dio.post<List<int>>(
        '/v1/tts',
        data: {'text': text},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'audio/mpeg'},
          validateStatus: (_) => true,
        ),
      ),
    );
    final bytes = response.data;
    final mediaType = response.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (response.statusCode != 200 ||
        mediaType != 'audio/mpeg' ||
        bytes == null ||
        bytes.isEmpty) {
      throw const TtsGenerationFailure('invalid_audio');
    }

    final file = File('${_temporaryDirectory().path}/$_fileName');
    await file.writeAsBytes(bytes, flush: true);
    _generatedFile = file;
    return file;
  }

  @override
  Future<void> dispose() async {
    final file = _generatedFile;
    if (file != null && await file.exists()) {
      await file.delete();
    }
    _generatedFile = null;
  }
}

Directory _systemTemporaryDirectory() => Directory.systemTemp;
