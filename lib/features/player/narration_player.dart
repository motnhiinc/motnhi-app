import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';

/// Drives narration for the pages of a story (§9.4.3). Plays segments in
/// `sort_order` and exposes [currentSegment] so the player can highlight the
/// spoken sentence (§7.1.2, §4.2 timing).
///
/// Audio source strategy (per the chosen slice):
///  * If a segment carries a bundled `audio_asset_id`, the real pre-generated
///    clip is played via [just_audio] — the production contract.
///  * Otherwise it falls back to on-device [FlutterTts]. This is a DEV-ONLY
///    stand-in until the content/TTS pipeline produces reviewed clips; the
///    spec forbids real-time TTS in child production sessions (§13.1, §18.2).
class NarrationPlayer {
  NarrationPlayer({AudioPlayer? filePlayer, FlutterTts? tts, AssetUrlResolver? resolver})
      : _file = filePlayer ?? AudioPlayer(),
        _tts = tts ?? FlutterTts(),
        _resolver = resolver;

  final AudioPlayer _file;
  final FlutterTts _tts;
  final AssetUrlResolver? _resolver;

  /// Resolved signed URLs for the current page, keyed by `audio_asset_id`.
  Map<String, String> _urlByAssetId = {};

  /// True when at least one segment cannot be played from a real clip and must
  /// use the DEV-ONLY TTS fallback. Pure so it is unit-testable without audio.
  static bool computeTtsFallback(
    List<NarrationSegment> segments,
    Map<String, String> urls,
  ) =>
      segments.any((s) => !s.hasAudioAsset || !urls.containsKey(s.audioAssetId));

  /// Index into [_segments] currently being spoken; -1 when idle.
  final ValueNotifier<int> currentSegmentIndex = ValueNotifier(-1);
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> isComplete = ValueNotifier(false);

  /// True when any segment fell back to TTS — surfaced in the UI so it's never
  /// mistaken for reviewed production audio.
  final ValueNotifier<bool> usingTtsFallback = ValueNotifier(false);

  List<NarrationSegment> _segments = const [];
  double _speedMultiplier = 1.0;
  String _languageCode = 'en';
  bool _ttsReady = false;

  int _cursor = 0;
  bool _running = false;
  Completer<void>? _segmentInterrupt;

  /// The segment currently highlighted, if any.
  NarrationSegment? get currentSegment {
    final i = currentSegmentIndex.value;
    return (i >= 0 && i < _segments.length) ? _segments[i] : null;
  }

  /// Load a page's segments and reset to the start.
  Future<void> load(
    List<NarrationSegment> segments, {
    double speedMultiplier = 1.0,
    String languageCode = 'en',
  }) async {
    await _haltLoop();
    _segments = segments;
    _speedMultiplier = speedMultiplier;
    _languageCode = languageCode;
    _cursor = 0;
    currentSegmentIndex.value = -1;
    isComplete.value = false;

    final ids = segments
        .where((s) => s.hasAudioAsset)
        .map((s) => s.audioAssetId!)
        .toList();
    _urlByAssetId = (_resolver != null && ids.isNotEmpty)
        ? await _resolver!.resolve(ids)
        : <String, String>{};
    usingTtsFallback.value = computeTtsFallback(segments, _urlByAssetId);
  }

  void setSpeedMultiplier(double value) => _speedMultiplier = value;

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(_languageCode == 'vi' ? 'vi-VN' : 'en-US');
    _ttsReady = true;
  }

  /// Start or resume playback from the current cursor.
  Future<void> play() async {
    if (_running) return;
    if (isComplete.value) {
      _cursor = 0;
      isComplete.value = false;
    }
    _running = true;
    isPlaying.value = true;
    await _runLoop();
  }

  Future<void> _runLoop() async {
    while (_running && _cursor < _segments.length) {
      currentSegmentIndex.value = _cursor;
      await _playSegment(_segments[_cursor]);
      if (!_running) return; // paused mid-segment
      _cursor++;
    }
    if (_cursor >= _segments.length) {
      _running = false;
      isPlaying.value = false;
      isComplete.value = true;
      currentSegmentIndex.value = -1;
    }
  }

  Future<void> _playSegment(NarrationSegment seg) async {
    _segmentInterrupt = Completer<void>();
    final interrupt = _segmentInterrupt!.future;
    final speed = (seg.speed * _speedMultiplier).clamp(0.5, 2.0);

    final url = seg.hasAudioAsset ? _urlByAssetId[seg.audioAssetId] : null;
    if (url != null) {
      try {
        await _file.setUrl(url);
        await _file.setSpeed(speed);
        final done = _file.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed);
        unawaited(_file.play());
        await Future.any([done, interrupt]);
      } catch (_) {
        // A missing/corrupt clip shouldn't break the story — fall through.
      }
    } else {
      await _ensureTts();
      await _tts.setSpeechRate(_ttsRate(speed));
      await _tts.setPitch(_pitchFor(seg.speakerKey));
      // awaitSpeakCompletion(true) makes speak() resolve when finished/stopped.
      await Future.any([_tts.speak(seg.text), interrupt]);
    }
  }

  /// Pause playback, holding position at the current segment.
  Future<void> pause() async {
    if (!_running) return;
    _running = false;
    isPlaying.value = false;
    await _interruptSegment();
  }

  /// Jump to a specific segment (e.g. tapped sentence or AR tap target).
  Future<void> seekToSegment(int index) async {
    if (index < 0 || index >= _segments.length) return;
    final wasPlaying = _running;
    await _haltLoop();
    _cursor = index;
    currentSegmentIndex.value = index;
    if (wasPlaying) await play();
  }

  /// Replay the current page from the beginning (§7.1.2 "replay page").
  Future<void> replay() async {
    await _haltLoop();
    _cursor = 0;
    isComplete.value = false;
    await play();
  }

  Future<void> _interruptSegment() async {
    await _tts.stop();
    await _file.pause();
    if (_segmentInterrupt != null && !_segmentInterrupt!.isCompleted) {
      _segmentInterrupt!.complete();
    }
  }

  Future<void> _haltLoop() async {
    _running = false;
    isPlaying.value = false;
    await _interruptSegment();
  }

  Future<void> dispose() async {
    await _haltLoop();
    await _file.dispose();
    await _tts.stop();
    currentSegmentIndex.dispose();
    isPlaying.dispose();
    isComplete.dispose();
    usingTtsFallback.dispose();
  }

  /// flutter_tts speech rate is ~0.5 == normal on both platforms; scale around
  /// that midpoint.
  static double _ttsRate(double speed) => (0.5 * speed).clamp(0.1, 1.0);

  /// Cheap per-speaker voice differentiation until real `voice_id` assets exist
  /// (§7.1.3). Narrator neutral; characters pitched apart.
  static double _pitchFor(String speakerKey) {
    final key = speakerKey.toLowerCase();
    if (key.contains('owl') || key.contains('wise')) return 0.8;
    if (key.contains('bunny') || key.contains('child')) return 1.4;
    if (key == 'narrator') return 1.0;
    return 1.1;
  }
}
