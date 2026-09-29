import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/sources/api_client.dart';
import 'scanned_page.dart';

class PageValidationResult {
  const PageValidationResult.approved(this.proof) : blocked = false;
  const PageValidationResult.blocked() : proof = null, blocked = true;

  final String? proof;
  final bool blocked;
}

class PageValidationClient {
  PageValidationClient(
    this._api, {
    required bool Function() hasEffectiveConsent,
    Future<Directory> Function()? temporaryDirectory,
  }) : _hasEffectiveConsent = hasEffectiveConsent,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final ApiClient _api;
  final bool Function() _hasEffectiveConsent;
  final Future<Directory> Function() _temporaryDirectory;
  final Set<Directory> _ownedDirectories = {};
  final Set<File> _ownedFiles = {};
  var _directorySequence = 0;
  bool _disposed = false;

  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId,
  ) async {
    _checkAccess(profileId);
    final response = await _api.send(
      () => _api.dio.post<Map<String, dynamic>>(
        '/v1/speakable-page/validate',
        data: {
          'profile_id': profileId,
          'image_base64': base64Encode(page.jpegBytes),
          'lines': [
            for (final line in page.lines)
              {
                'text': line.text,
                'left': line.left,
                'top': line.top,
                'width': line.width,
                'height': line.height,
              },
          ],
        },
      ),
    );
    _checkAccess(profileId);
    final data = response.data;
    if (data?['status'] == 'blocked') {
      return const PageValidationResult.blocked();
    }
    if (data?['status'] != 'approved' || data?['proof'] is! String) {
      throw const FormatException('validation_unavailable');
    }
    return PageValidationResult.approved(data!['proof'] as String);
  }

  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines,
  ) async {
    _checkAccess(profileId);
    final response = await _api.send(
      () => _api.dio.post<List<int>>(
        '/v1/speakable-page/audio',
        data: {'profile_id': profileId, 'proof': proof, 'lines': lines},
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    _checkAccess(profileId);
    if (!((response.headers.value(Headers.contentTypeHeader) ?? '')
        .toLowerCase()
        .startsWith('application/zip'))) {
      throw const FormatException('invalid_audio_bundle');
    }
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('empty_bundle');
    }
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
        files.any((file) => file.size == 0 || file.size > 2 * 1024 * 1024)) {
      throw const FormatException('invalid_audio_bundle');
    }
    final directory = await _directory();
    final output = <File>[];
    try {
      for (var index = 0; index < files.length; index++) {
        _ensureLive();
        final file = File('${directory.path}/${expected[index]}');
        await file.writeAsBytes(
          Uint8List.fromList(files[index].content as List<int>),
        );
        _ownedFiles.add(file);
        output.add(file);
      }
      return output;
    } catch (_) {
      for (final file in output) {
        _ownedFiles.remove(file);
        if (await file.exists()) await file.delete();
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      _ownedDirectories.remove(directory);
      rethrow;
    }
  }

  Future<Directory> _directory() async {
    final directory = Directory(
      '${(await _temporaryDirectory()).path}/speakable-page-${DateTime.now().microsecondsSinceEpoch}-${_directorySequence++}',
    );
    await directory.create(recursive: true);
    _ownedDirectories.add(directory);
    return directory;
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final file in _ownedFiles.toList()) {
      if (await file.exists()) {
        await file.delete();
      }
    }
    _ownedFiles.clear();
    for (final directory in _ownedDirectories.toList()) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    _ownedDirectories.clear();
  }

  void _ensureLive() {
    if (_disposed) throw StateError('page validation client disposed');
  }

  void _checkAccess(String profileId) {
    _ensureLive();
    final consent = _hasEffectiveConsent();
    if (profileId.trim().isEmpty || !consent) {
      throw StateError('page_reading_not_authorized');
    }
  }
}
