import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../data/sources/api_client.dart';

abstract interface class TtsClient {
  /// Generates narration audio. [fileName] lets a caller keep several clips
  /// alive at once — the player holds one per page, and a page turn must not
  /// overwrite a file just_audio is still reading. Omitting it reuses the
  /// single-clip name the scan-any-page flow has always used.
  Future<File> generate(String confirmedText, {String? fileName});

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
  static final _mpegContentType = RegExp(
    r'''^audio/mpeg\s*(?:;\s*[!#$%&'*+.^_`|~0-9A-Za-z-]+\s*=\s*(?:[!#$%&'*+.^_`|~0-9A-Za-z-]+|"(?:[^"\\]|\\.)*")\s*)*$''',
    caseSensitive: false,
  );

  final ApiClient _apiClient;
  final Directory Function() _temporaryDirectory;
  Future<void> _operations = Future.value();
  var _nextOperationId = 0;
  /// Absolute path -> the operation id that created it. Keyed by path rather
  /// than kept as a single file so several named clips can coexist; dispose
  /// still only deletes files created by an *earlier* operation.
  final Map<String, int> _generatedFileOwners = {};

  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    final text = confirmedText.trim();
    if (text.isEmpty || text.runes.length > 4000) {
      return Future.error(const TtsGenerationFailure('invalid_text'));
    }

    final operationId = ++_nextOperationId;
    final completion = Completer<File>();
    _enqueue(() async {
      try {
        completion.complete(
          await _generate(text, operationId, fileName ?? _fileName),
        );
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  Future<File> _generate(String text, int operationId, String fileName) async {
    late final Response<List<int>> response;
    try {
      response = await _apiClient.send<List<int>>(
        () => _apiClient.dio.post<List<int>>(
          '/v1/tts',
          data: {'text': text},
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Accept': 'audio/mpeg'},
          ),
        ),
      );
    } on DioException catch (error) {
      throw TtsGenerationFailure(_failureCode(error));
    }
    final bytes = response.data;
    if (response.statusCode != 200 ||
        !_hasValidContentType(response.headers) ||
        bytes == null ||
        bytes.isEmpty) {
      throw const TtsGenerationFailure('invalid_audio');
    }

    final directory = _temporaryDirectory();
    final file = File('${directory.path}/$fileName');
    final temporaryFile =
        File('${directory.path}/.$fileName.$operationId.tmp');
    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(file.path);
      _generatedFileOwners[file.path] = operationId;
      return file;
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  @override
  Future<void> dispose() {
    final operationId = ++_nextOperationId;
    final completion = Completer<void>();
    _enqueue(() async {
      try {
        for (final entry in _generatedFileOwners.entries.toList()) {
          if (entry.value >= operationId) continue;
          final file = File(entry.key);
          if (await file.exists()) await file.delete();
        }
        _generatedFileOwners.clear();
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  void _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation());
  }
}

String _failureCode(DioException error) {
  switch (error.response?.statusCode) {
    case 401:
    case 403:
      return 'authentication';
    case 429:
      return 'rate_limited';
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'timeout';
    case DioExceptionType.connectionError:
      return 'backend_unreachable';
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return 'upstream_failed';
    case DioExceptionType.unknown:
      return error.error is SocketException
          ? 'backend_unreachable'
          : 'upstream_failed';
  }
}

bool _hasValidContentType(Headers headers) {
  final values = headers[Headers.contentTypeHeader];
  if (values == null || values.length != 1) return false;
  final value = values.single.trim();
  return HttpTtsClient._mpegContentType.hasMatch(value);
}

Directory _systemTemporaryDirectory() => Directory.systemTemp;
