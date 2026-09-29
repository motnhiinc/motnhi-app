import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';
import 'narration_audio_fetcher.dart';

/// Drives narration for the pages of a story (§9.4.3). Plays segments in
/// `sort_order` and exposes [currentSegment] so the player can highlight the
/// spoken sentence (§7.1.2, §4.2 timing).
///
/// Audio source strategy, in precedence order:
///  * If a segment carries a bundled `audio_asset_id`, the real pre-generated
///    clip is played via [just_audio] — the production contract.
///  * Else, if a [NarrationAudioFetcher] is supplied, a clip generated for this
///    segment is played from disk. Only authored (user-captured) stories get a
///    fetcher; curated stories never do.
///  * Otherwise it falls back to on-device [FlutterTts]. For curated content
///    this is a DEV-ONLY stand-in until the content/TTS pipeline produces
///    reviewed clips (§13.1, §18.2); for an authored story it means the
///    narration fetch failed and playback degraded.
class NarrationPlayer {
  NarrationPlayer({
    AudioPlayer? filePlayer,
    FlutterTts? tts,
    AssetUrlResolver? resolver,
    NarrationAudioFetcher? fetcher,
  })  : _file = filePlayer ?? AudioPlayer(),
        _tts = tts ?? FlutterTts(),
        _resolver = resolver,
        _fetcher = fetcher;

  final AudioPlayer _file;
  final FlutterTts _tts;
  final AssetUrlResolver? _resolver;
  final NarrationAudioFetcher? _fetcher;

  /// Resolved signed URLs for the current page, keyed by `audio_asset_id`.
  Map<String, String> _urlByAssetId = {};

  /// Locally generated clips for the current page, keyed by segment id.
  Map<String, String> _pathBySegmentId = {};

  @visibleForTesting
  Map<String, String> get debugFetchedPaths => _pathBySegmentId;

  /// True when at least one segment can play from neither a registered clip
  /// nor a locally fetched one, and must therefore use on-device TTS. Pure so
  /// it is unit-testable without audio.
  static bool computeTtsFallback(
    List<NarrationSegment> segments,
    Map<String, String> urls,
    Map<String, String> fetched,
  ) =>
      segments.any((s) =>
          !(s.hasAudioAsset && urls.containsKey(s.audioAssetId)) &&
          !fetched.containsKey(s.id));

  /// Index into [_segments] currently being spoken; -1 when idle.
  final ValueNotifier<int> currentSegmentIndex = ValueNotifier(-1);
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> isStarting = ValueNotifier(false);
  final ValueNotifier<bool> isComplete = ValueNotifier(false);

  /// True when any segment fell back to TTS — surfaced in the UI so it's never
  /// mistaken for reviewed production audio.
  final ValueNotifier<bool> usingTtsFallback = ValueNotifier(false);

  /// True while a page's audio is being resolved or fetched. The player UI
  /// disables playback controls on this, so a tap during a multi-second TTS
  /// fetch cannot start device TTS a moment before the clip lands.
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  List<NarrationSegment> _segments = const [];
  double _speedMultiplier = 1.0;
  String _languageCode = 'en';
  bool _ttsReady = false;

  int _cursor = 0;
  var _loadGeneration = 0;
  var _runGeneration = 0;
  bool _running = false;
  String? _preparedSegmentId;
  Future<void> _preloadTail = Future.value();
  Completer<void>? _segmentInterrupt;

  /// The segment currently highlighted, if any.
  NarrationSegment? get currentSegment {
    final i = currentSegmentIndex.value;
    return (i >= 0 && i < _segments.length) ? _segments[i] : null;
  }

  /// Load a page's segments and reset to the start.
  ///
  /// Every await is followed by a generation check before any field write: the
  /// player fires this per page turn without awaiting it, and with a TTS fetch
  /// in the middle a stale load could otherwise overwrite the newer page's
  /// audio maps seconds later.
  Future<void> load(
    List<NarrationSegment> segments, {
    double speedMultiplier = 1.0,
    String languageCode = 'en',
  }) async {
    final generation = ++_loadGeneration;
    await _haltLoop();
    if (generation != _loadGeneration) return;

    _segments = segments;
    _speedMultiplier = speedMultiplier;
    _languageCode = languageCode;
    _cursor = 0;
    _preparedSegmentId = null;
    currentSegmentIndex.value = -1;
    isComplete.value = false;
    isLoading.value = true;

    try {
      final ids = segments
          .where((s) => s.hasAudioAsset)
          .map((s) => s.audioAssetId!)
          .toList();
      final resolver = _resolver;
      final urls = (resolver != null && ids.isNotEmpty)
          ? await resolver.resolve(ids)
          : <String, String>{};
      if (generation != _loadGeneration) return;

      final fetcher = _fetcher;
      final fetched = <String, String>{};
      if (fetcher != null) {
        for (final segment in segments) {
          if (segment.hasAudioAsset && urls.containsKey(segment.audioAssetId)) {
            continue;
          }
          final path = await fetcher.pathFor(segment);
          if (generation != _loadGeneration) return;
          if (path != null) fetched[segment.id] = path;
        }
      }

      _urlByAssetId = urls;
      _pathBySegmentId = fetched;
      usingTtsFallback.value =
          computeTtsFallback(segments, _urlByAssetId, _pathBySegmentId);
      // Buffer the first clip while the page is loading, before Play is tapped.
      if (segments.isNotEmpty) {
        final first = segments.first;
        final url = first.hasAudioAsset ? urls[first.audioAssetId] : null;
        final path = fetched[first.id];
        if (url != null || path != null) {
          // A page turn may begin while the previous setUrl is still pending.
          // Serialize those native calls so an older page cannot win the race.
          final previousPreload = _preloadTail;
          final finished = Completer<void>();
          _preloadTail = finished.future;
          try {
            await previousPreload;
            if (generation != _loadGeneration) return;
            if (url != null) {
              await _file.setUrl(url);
            } else {
              await _file.setFilePath(path!);
            }
            if (generation != _loadGeneration) return;
            _preparedSegmentId = first.id;
          } catch (_) {
            if (generation != _loadGeneration) return;
            // A broken clip must not strand Play; use the device voice.
            if (url != null) _urlByAssetId.remove(first.audioAssetId);
            if (path != null) _pathBySegmentId.remove(first.id);
            usingTtsFallback.value = true;
          } finally {
            finished.complete();
          }
        }
      }
    } finally {
      if (generation == _loadGeneration) isLoading.value = false;
    }
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
    isStarting.value = true;
    await _runLoop(++_runGeneration);
  }

  Future<void> _runLoop(int generation) async {
    while (_running &&
        generation == _runGeneration &&
        _cursor < _segments.length) {
      currentSegmentIndex.value = _cursor;
      await _playSegment(_segments[_cursor], generation);
      if (!_running || generation != _runGeneration) return;
      _cursor++;
    }
    if (_cursor >= _segments.length && generation == _runGeneration) {
      // just_audio can remain in playing=true after reaching completed; pause
      // before the next page is buffered so setUrl cannot start it early.
      await _file.pause();
      if (generation != _runGeneration) return;
      _running = false;
      isPlaying.value = false;
      isStarting.value = false;
      isComplete.value = true;
      currentSegmentIndex.value = -1;
    }
  }

  Future<void> _playSegment(NarrationSegment seg, int generation) async {
    _segmentInterrupt = Completer<void>();
    final interrupt = _segmentInterrupt!.future;
    final speed = (seg.speed * _speedMultiplier).clamp(0.5, 2.0);

    final url = seg.hasAudioAsset ? _urlByAssetId[seg.audioAssetId] : null;
    final path = _pathBySegmentId[seg.id];

    if (url != null || path != null) {
      try {
        if (_preparedSegmentId == seg.id) {
          await _file.seek(Duration.zero);
        } else if (url != null) {
          await _file.setUrl(url);
        } else {
          await _file.setFilePath(path!);
        }
        if (!_running || generation != _runGeneration) return;
        _preparedSegmentId = seg.id;
        await _file.setSpeed(speed);
        if (!_running || generation != _runGeneration) return;
        final done = _file.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed);
        unawaited(_file.play());
        await Future.any([
          _file.playingStream.firstWhere((playing) => playing),
          interrupt,
        ]);
        if (!_running || generation != _runGeneration) {
          await _file.pause();
          return;
        }
        isStarting.value = false;
        isPlaying.value = true;
        await Future.any([done, interrupt]);
        return;
      } catch (_) {
        if (generation != _runGeneration) return;
        // A missing or corrupt clip must not leave the page silent. With one
        // segment per page, skipping here means no narration at all and, on the
        // last page, an instant completion dialog. Fall through to device TTS.
      }
    }

    await _ensureTts();
    await _tts.setSpeechRate(_ttsRate(speed));
    await _tts.setPitch(_pitchFor(seg.speakerKey));
    if (!_running || generation != _runGeneration) return;
    isStarting.value = false;
    isPlaying.value = true;
    // awaitSpeakCompletion(true) makes speak() resolve when finished/stopped.
    await Future.any([_tts.speak(seg.text), interrupt]);
  }

  /// Pause playback, holding position at the current segment.
  Future<void> pause() async {
    if (!_running) return;
    _runGeneration++;
    _running = false;
    isPlaying.value = false;
    isStarting.value = false;
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
    _runGeneration++;
    _running = false;
    isPlaying.value = false;
    isStarting.value = false;
    await _interruptSegment();
  }

  Future<void> dispose() async {
    await _haltLoop();
    await _fetcher?.dispose();
    await _file.dispose();
    await _tts.stop();
    currentSegmentIndex.dispose();
    isPlaying.dispose();
    isStarting.dispose();
    isComplete.dispose();
    usingTtsFallback.dispose();
    isLoading.dispose();
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
