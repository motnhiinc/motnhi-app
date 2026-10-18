import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/sources/api_client.dart';
import 'scanned_page.dart';

class PageValidationResult {
  const PageValidationResult.approved(this.proof, {this.recognizedPage})
    : blocked = false,
      reason = null;
  const PageValidationResult.blocked([this.reason])
    : proof = null,
      recognizedPage = null,
      blocked = true;

  final String? proof;
  final bool blocked;
  final String? reason;
  final ScannedPage? recognizedPage;
}

abstract interface class PageReadingClient {
  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  });
  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  });
  Future<void> dispose();
}

class PageRequestFailure implements Exception {
  const PageRequestFailure(this.reason);
  final String reason;
}

class PageValidationClient implements PageReadingClient {
  PageValidationClient(
    this._api, {
    Future<Directory> Function()? temporaryDirectory,
    this.onExtraction,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final ApiClient _api;
  final void Function(int elapsedMs)? onExtraction;
  final Future<Directory> Function() _temporaryDirectory;
  final Set<Directory> _ownedDirectories = {};
  final Set<File> _ownedFiles = {};
  bool _disposed = false;

  @override
  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    _checkAccess(profileId);
    final response = await _api.send(
      () => _api.dio.post<Map<String, dynamic>>(
        '/v1/speakable-page/validate',
        data: {
          'profile_id': profileId,
          'ocr_provider': 'google_vision',
          'content_language': ?contentLanguage,
          'image_base64': base64Encode(page.jpegBytes),
        },
        cancelToken: cancelToken,
        options: _options(
          attemptId,
          operationId,
        ).copyWith(receiveTimeout: const Duration(seconds: 60)),
      ),
    );
    _checkAccess(profileId);
    _checkCancellation(cancelToken);
    final data = response.data;
    if (data?['status'] == 'blocked') {
      return PageValidationResult.blocked(data?['reason'] as String?);
    }
    if (data?['status'] != 'approved' || data?['proof'] is! String) {
      throw const FormatException('validation_unavailable');
    }
    // Never fall back to native text if the cloud OCR response is incomplete.
    final recognizedPage = ScannedPage.fromMap({
      'imageBytes': page.jpegBytes,
      'width': page.width,
      'height': page.height,
      'lines': data!['recognized_lines'],
      'quality': page.quality,
      'nativeProcessingMs': page.nativeProcessingMs,
      'diagnostics': page.diagnostics,
    });
    return PageValidationResult.approved(
      data['proof'] as String,
      recognizedPage: recognizedPage,
    );
  }

  @override
  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    _checkAccess(profileId);
    final response = await _api.send(
      () => _api.dio.post<List<int>>(
        '/v1/speakable-page/audio',
        data: {
          'profile_id': profileId,
          'proof': proof,
          'lines': lines,
          'content_language': ?contentLanguage,
        },
        cancelToken: cancelToken,
        options: _options(attemptId, operationId, bytes: true),
      ),
    );
    _checkAccess(profileId);
    _checkCancellation(cancelToken);
    if (!((response.headers.value(Headers.contentTypeHeader) ?? '')
        .toLowerCase()
        .startsWith('application/zip'))) {
      throw const FormatException('invalid_audio_bundle');
    }
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('empty_bundle');
    }
    final extractionClock = Stopwatch()..start();
    final entries = ZipDecoder().decodeBytes(bytes);
    final expected = [
      for (var i = 0; i < lines.length; i++)
        '${i.toString().padLeft(3, '0')}.mp3',
    ];
    final files = entries.files.where((entry) => !entry.isDirectory).toList();
    if (files.length != expected.length ||
        List.generate(files.length, (i) => files[i].name).toSet().length !=
            expected.length ||
        files.map((file) => file.name).toList().toString() !=
            expected.toString() ||
        files.any((file) => file.size == 0 || file.size > 2 * 1024 * 1024) ||
        files.fold<int>(0, (sum, file) => sum + file.size) > 32 * 1024 * 1024) {
      throw const FormatException('invalid_audio_bundle');
    }
    final directory = await _directory();
    final output = <File>[];
    try {
      for (var index = 0; index < files.length; index++) {
        _ensureLive();
        _checkCancellation(cancelToken);
        final file = File('${directory.path}/${expected[index]}');
        await file.writeAsBytes(
          Uint8List.fromList(files[index].content as List<int>),
        );
        _ownedFiles.add(file);
        output.add(file);
        _ensureLive();
        _checkCancellation(cancelToken);
      }
      onExtraction?.call(extractionClock.elapsedMilliseconds);
      return output;
    } catch (_) {
      for (final file in output) {
        _ownedFiles.remove(file);
        await _deleteIfPresent(file);
      }
      await _deleteIfPresent(directory);
      _ownedDirectories.remove(directory);
      rethrow;
    }
  }

  Options _options(
    String? attemptId,
    String? operationId, {
    bool bytes = false,
  }) => Options(
    responseType: bytes ? ResponseType.bytes : ResponseType.json,
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 35),
    headers: {
      'X-Scan-Attempt-Id': ?attemptId,
      'X-Scan-Operation-Id': ?operationId,
    },
  );

  Future<Directory> _directory() async {
    final root = await _temporaryDirectory();
    _ensureLive();
    final directory = await root.createTemp('speakable-page-');
    if (_disposed) {
      await _deleteIfPresent(directory);
      throw StateError('page validation client disposed');
    }
    _ownedDirectories.add(directory);
    return directory;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final file in _ownedFiles.toList()) {
      await _deleteIfPresent(file);
    }
    _ownedFiles.clear();
    for (final directory in _ownedDirectories.toList()) {
      await _deleteIfPresent(directory);
    }
    _ownedDirectories.clear();
  }

  Future<void> _deleteIfPresent(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: entity is Directory);
    } on FileSystemException {
      if (await entity.exists()) rethrow;
    }
  }

  void _ensureLive() {
    if (_disposed) throw StateError('page validation client disposed');
  }

  void _checkCancellation(CancelToken? token) {
    if (token?.isCancelled == true) throw const PageRequestFailure('cancelled');
  }

  void _checkAccess(String profileId) {
    _ensureLive();
    if (profileId.trim().isEmpty) {
      throw StateError('page_reading_not_authorized');
    }
  }
}
