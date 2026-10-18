import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'line_audio_player.dart';
import 'native_scan_service.dart';
import 'page_validation_client.dart';
import 'scanned_page.dart';

enum ScanPagePhase {
  scanning,
  validating,
  preparingAudio,
  ready,
  playing,
  paused,
  completed,
  blocked,
  failed,
  setup,
}

enum ScanRecovery { retake, validation, audio, anotherPage }

/// Session-only state owner for the active route. No page content is persisted.
class ScanPageCoordinator extends ChangeNotifier {
  ScanPageCoordinator({
    required this.scanner,
    required this.client,
    required this.player,
    this.onCancelled,
    this.diagnostic,
  });

  final ScanService scanner;
  final PageReadingClient client;
  final ScanPagePlayer player;
  final VoidCallback? onCancelled;
  final void Function(Map<String, Object>)? diagnostic;
  ScanPagePhase phase = ScanPagePhase.scanning;
  ScanRecovery recovery = ScanRecovery.retake;
  ScannedPage? _page;
  ScannedPage? get page => _proof == null ? null : _page;
  String? reason;
  String _contentLanguage = 'vi';
  String get contentLanguage => _contentLanguage;
  String? _profileId;
  String? _proof;
  String _attemptId = '';
  String _operationId = '';
  Stopwatch _stageClock = Stopwatch();
  int _generation = 0;
  int _retry = 0;
  bool _disposed = false;
  CancelToken? _cancel;
  final List<File> _clips = [];
  Future<void> _media = Future.value();
  Stopwatch? _captureToReady;
  Stopwatch? _listenClock;

  bool _live(int generation) => !_disposed && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _stage(String stage, Stopwatch clock) => diagnostic?.call({
    'attempt_id': _attemptId,
    'operation_id': _operationId,
    'stage': stage,
    'retry': _retry,
    'elapsed_ms':
        clock.elapsedMilliseconds +
        (stage == 'capture_return_to_ready'
            ? (_page?.nativeProcessingMs ?? 0)
            : 0),
    if (_page != null) ...{
      'image_width': _page!.width,
      'image_height': _page!.height,
      'image_bytes': _page!.jpegBytes.length,
      'line_count': _page!.lines.length,
      'character_count': _page!.lines.fold<int>(
        0,
        (sum, line) => sum + line.text.runes.length,
      ),
      'quality_version': _page!.quality?['version'] is int
          ? _page!.quality!['version'] as int
          : 0,
      for (final key in [
        'app_version',
        'android_sdk',
        'device_model',
        'cold_run',
        'network_category',
      ])
        if (_page!.diagnostics[key] is String ||
            _page!.diagnostics[key] is num ||
            _page!.diagnostics[key] is bool)
          key: _page!.diagnostics[key] as Object,
    },
  });

  Future<void> _mediaAction(Future<void> Function() action) {
    final next = _media.then((_) => action());
    _media = next.catchError((Object _) {});
    return next;
  }

  Future<void> scan(String? profileId, {String? language}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _cancel?.cancel();
    _attemptId = const Uuid().v4();
    _operationId = const Uuid().v4();
    _stageClock = Stopwatch()..start();
    _retry = 0;
    _proof = null;
    _page = null;
    reason = null;
    if (language != null) _contentLanguage = language;
    _profileId = profileId;
    phase = profileId == null ? ScanPagePhase.setup : ScanPagePhase.scanning;
    _emit();
    await _mediaAction(player.stop);
    await _clearClips();
    if (!_live(generation) || profileId == null) return;
    try {
      final capture = await (scanner is NativeScanService
          ? (scanner as NativeScanService).scanWithAttempt(_attemptId)
          : scanner.scanAndRecognize());
      if (!_live(generation)) return;
      _captureToReady = Stopwatch()..start();
      _page = capture.normalized();
      await _validate(generation);
    } on ScanCancelled {
      if (_live(generation)) onCancelled?.call();
    } catch (error) {
      _fail(error, ScanRecovery.retake, generation);
    }
  }

  Future<void> retry() async {
    if (_disposed || phase != ScanPagePhase.failed || _page == null) return;
    final generation = ++_generation;
    _cancel?.cancel();
    _retry++;
    reason = null;
    if (recovery == ScanRecovery.audio && _proof != null) {
      await _audio(generation);
    } else if (recovery == ScanRecovery.validation) {
      await _validate(generation);
    }
  }

  Future<void> _validate(int generation) async {
    phase = ScanPagePhase.validating;
    _proof = null;
    _emit();
    final clock = Stopwatch()..start();
    _stageClock = clock;
    _operationId = const Uuid().v4();
    _cancel = CancelToken();
    try {
      final result = await client.validate(
        _page!,
        _profileId!,
        contentLanguage: contentLanguage,
        cancelToken: _cancel,
        attemptId: _attemptId,
        operationId: _operationId,
      );
      if (!_live(generation)) return;
      _stage('validation_round_trip', clock);
      if (result.blocked || result.proof == null) {
        reason = result.reason ?? 'content_unsuitable';
        recovery = reason == 'content_unsuitable'
            ? ScanRecovery.anotherPage
            : ScanRecovery.retake;
        _page = null;
        phase = ScanPagePhase.blocked;
        _emit();
        return;
      }
      _proof = result.proof;
      _page = result.recognizedPage ?? _page;
      await _audio(generation);
    } catch (error) {
      _fail(error, ScanRecovery.validation, generation);
    }
  }

  Future<void> _audio(int generation) async {
    phase = ScanPagePhase.preparingAudio;
    _emit();
    final clock = Stopwatch()..start();
    _stageClock = clock;
    _operationId = const Uuid().v4();
    _cancel = CancelToken();
    try {
      final clips = await client.prepareAudio(
        _proof!,
        _profileId!,
        _page!.lines.map((l) => l.text).toList(),
        contentLanguage: contentLanguage,
        cancelToken: _cancel,
        attemptId: _attemptId,
        operationId: _operationId,
      );
      if (!_live(generation)) {
        await _delete(clips);
        return;
      }
      if (clips.length != _page!.lines.length) {
        await _delete(clips);
        throw const PageRequestFailure('invalid_audio_bundle');
      }
      _stage('audio_round_trip_extraction', clock);
      await _clearClips();
      if (!_live(generation)) {
        await _delete(clips);
        return;
      }
      _clips.addAll(clips);
      final loadClock = Stopwatch()..start();
      await _mediaAction(() async {
        if (_live(generation)) await player.load(clips);
      });
      if (!_live(generation)) return;
      _stage('player_loading', loadClock);
      phase = ScanPagePhase.ready;
      if (_captureToReady != null) {
        _stage('capture_return_to_ready', _captureToReady!);
      }
      _emit();
    } catch (error) {
      if (!_live(generation)) return;
      final code = _code(error);
      try {
        await _mediaAction(() async {
          if (_live(generation)) await player.stop();
        });
      } catch (_) {
        /* Preserve the failed stage's original reason. */
      }
      if (!_live(generation)) return;
      await _clearClips();
      if (!_live(generation)) return;
      if (code == 'page_approval_expired') {
        _proof = null;
        _fail(error, ScanRecovery.validation, generation);
      } else if (code == 'page_approval_invalid') {
        _proof = null;
        _fail(error, ScanRecovery.retake, generation);
      } else {
        _fail(error, ScanRecovery.audio, generation);
      }
    }
  }

  String _code(Object error) {
    if (error is ScanFailure) return error.code;
    if (error is PageRequestFailure) return error.reason;
    if (error is DioException) {
      dynamic data = error.response?.data;
      if (data is List<int>) {
        try {
          data = jsonDecode(utf8.decode(data));
        } catch (_) {
          data = null;
        }
      }
      const codes = {
        'page_approval_expired',
        'page_approval_invalid',
        'provider_timeout',
        'provider_capacity',
        'provider_unavailable',
        'provider_failed',
        'speech_configuration_invalid',
      };
      final code = data is Map ? (data['reason'] ?? data['detail']) : null;
      if (codes.contains(code)) return code as String;
      if ({401, 403, 404}.contains(error.response?.statusCode)) {
        return 'page_reading_not_authorized';
      }
      if ({400, 422}.contains(error.response?.statusCode)) {
        return 'invalid_page';
      }
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'provider_timeout';
      }
      return 'network_unavailable';
    }
    return 'processing_failed';
  }

  void _fail(Object error, ScanRecovery action, int generation) {
    if (!_live(generation)) return;
    reason = _code(error);
    diagnostic?.call({
      'attempt_id': _attemptId,
      'operation_id': _operationId,
      'stage': phase.name,
      'reason': reason!,
      'retry': _retry,
      'elapsed_ms': _stageClock.elapsedMilliseconds,
    });
    recovery = reason == 'invalid_page' ? ScanRecovery.retake : action;
    if (reason == 'page_reading_not_authorized') {
      _cancel?.cancel();
      _proof = null;
      _page = null;
      phase = ScanPagePhase.setup;
      unawaited(_clearClips());
      unawaited(_mediaAction(player.stop));
    } else {
      phase = ScanPagePhase.failed;
    }
    _emit();
  }

  void bindPlayback() {
    player.playing.addListener(_playbackChanged);
    player.completed.addListener(_playbackChanged);
  }

  void _playbackChanged() {
    if (_disposed ||
        !{
          ScanPagePhase.ready,
          ScanPagePhase.playing,
          ScanPagePhase.paused,
          ScanPagePhase.completed,
        }.contains(phase)) {
      return;
    }
    phase = player.completed.value
        ? ScanPagePhase.completed
        : player.playing.value
        ? ScanPagePhase.playing
        : ScanPagePhase.paused;
    _emit();
  }

  Future<void> listen() async {
    if (phase != ScanPagePhase.ready || _proof == null) return;
    // just_audio's Future completes at the END, not the start, of playback.
    _listenClock = Stopwatch()..start();
    final generation = _generation;
    unawaited(
      player.play().catchError(
        (Object error) => _fail(error, ScanRecovery.audio, generation),
      ),
    );
  }

  void recordFirstPlaybackProgress() {
    if (!_disposed && _listenClock != null) {
      _stage('listen_to_first_playback_progress', _listenClock!);
      _listenClock = null;
    }
  }

  void recordExtraction(int elapsedMs) {
    if (!_disposed) {
      diagnostic?.call({
        'attempt_id': _attemptId,
        'operation_id': _operationId,
        'stage': 'bundle_extraction',
        'retry': _retry,
        'elapsed_ms': elapsedMs,
      });
    }
  }

  Future<void> pause() async {
    final generation = _generation;
    try {
      await player.pause();
    } catch (error) {
      _fail(error, ScanRecovery.audio, generation);
    }
  }

  void _startPlayback(Future<void> Function() action) {
    final generation = _generation;
    unawaited(
      action().catchError(
        (Object error) => _fail(error, ScanRecovery.audio, generation),
      ),
    );
  }

  void resume() => _startPlayback(player.resume);
  void replay() => _startPlayback(player.replay);

  Future<void> _delete(List<File> files) async {
    for (final file in files) {
      try {
        await file.delete();
      } on FileSystemException {
        // Disposal and a stale response may both finish cleanup of this file.
        if (await file.exists()) rethrow;
      }
    }
  }

  Future<void> _clearClips() async {
    final files = _clips.toList();
    _clips.clear();
    await _delete(files);
  }

  Future<void> close() async {
    if (_disposed) return;
    _generation++;
    _cancel?.cancel();
    _page = null;
    _proof = null;
    phase = ScanPagePhase.setup;
    _emit();
    _disposed = true;
    player.playing.removeListener(_playbackChanged);
    player.completed.removeListener(_playbackChanged);
    await _mediaAction(player.stop);
    await _clearClips();
    await client.dispose();
    await player.dispose();
  }
}
