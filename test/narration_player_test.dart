import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/player/narration_audio_fetcher.dart';
import 'package:storybook_ar/features/player/narration_player.dart';

NarrationSegment _seg(String id, {String? audioAssetId}) => NarrationSegment(
  id: id,
  storyId: 's',
  pageId: 'p',
  speakerKey: 'narrator',
  text: 'hello',
  voiceId: 'v',
  audioAssetId: audioAssetId,
  sortOrder: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no fallback when every segment has a resolved URL', () {
    final segs = [
      _seg('a', audioAssetId: 'aud_a'),
      _seg('b', audioAssetId: 'aud_b'),
    ];
    final urls = {'aud_a': 'http://x/a', 'aud_b': 'http://x/b'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls, const {}), isFalse);
  });

  test('fallback when a segment has an asset id but no resolved URL', () {
    final segs = [
      _seg('a', audioAssetId: 'aud_a'),
      _seg('b', audioAssetId: 'aud_b'),
    ];
    final urls = {'aud_a': 'http://x/a'}; // aud_b unresolved
    expect(NarrationPlayer.computeTtsFallback(segs, urls, const {}), isTrue);
  });

  test('fallback when a segment has no asset id at all', () {
    final segs = [_seg('a', audioAssetId: 'aud_a'), _seg('b')];
    final urls = {'aud_a': 'http://x/a'};
    expect(NarrationPlayer.computeTtsFallback(segs, urls, const {}), isTrue);
  });

  test('no fallback when segments list is empty', () {
    expect(NarrationPlayer.computeTtsFallback([], const {}, const {}), isFalse);
  });

  test('fallback for an all-TTS page (no asset ids anywhere)', () {
    final segs = [_seg('a'), _seg('b')]; // neither has an audioAssetId
    expect(
      NarrationPlayer.computeTtsFallback(segs, const {}, const {}),
      isTrue,
    );
  });

  test('no fallback when a fetched clip covers a segment with no asset id', () {
    final segs = [_seg('a')];
    expect(
      NarrationPlayer.computeTtsFallback(segs, const {}, {'a': '/tmp/a.mp3'}),
      isFalse,
    );
  });

  test('fallback when only some segments have a fetched clip', () {
    final segs = [_seg('a'), _seg('b')];
    expect(
      NarrationPlayer.computeTtsFallback(segs, const {}, {'a': '/tmp/a.mp3'}),
      isTrue,
    );
  });

  test('a registered clip still wins over a missing fetch', () {
    final segs = [_seg('a', audioAssetId: 'aud_a')];
    expect(
      NarrationPlayer.computeTtsFallback(segs, {
        'aud_a': 'http://x/a',
      }, const {}),
      isFalse,
    );
  });

  test('a stale load does not overwrite a newer page state', () async {
    final fetcher = _ControllableFetcher();
    final player = NarrationPlayer(
      filePlayer: _StubAudioPlayer(),
      tts: _StubTts(),
      fetcher: fetcher,
    );
    addTearDown(player.dispose);

    final pageOne = [_seg('a')];
    final pageTwo = [_seg('b')];

    final staleLoad = player.load(pageOne); // in flight, awaiting the fetch
    await Future<void>.delayed(Duration.zero);
    final newerLoad = player.load(pageTwo);
    await Future<void>.delayed(Duration.zero);

    // The stale page's fetch resolves last — it must not write anything.
    fetcher.complete('b', '/tmp/b.mp3');
    fetcher.complete('a', '/tmp/a.mp3');
    await Future.wait([staleLoad, newerLoad]);

    expect(
      player.debugFetchedPaths.containsKey('a'),
      isFalse,
      reason: 'the stale load must not write into the current page state',
    );
    expect(player.debugFetchedPaths.containsKey('b'), isTrue);
  });

  test('a load with no fetcher behaves exactly as before', () async {
    final player = NarrationPlayer(
      filePlayer: _StubAudioPlayer(),
      tts: _StubTts(),
    );
    addTearDown(player.dispose);

    await player.load([_seg('a')]);

    expect(player.debugFetchedPaths, isEmpty);
    expect(player.usingTtsFallback.value, isTrue);
  });

  test('load buffers the first resolved clip before Play', () async {
    final audio = _StubAudioPlayer();
    final player = NarrationPlayer(
      filePlayer: audio,
      tts: _StubTts(),
      resolver: _FixedResolver(),
    );
    addTearDown(player.dispose);

    await player.load([_seg('a', audioAssetId: 'aud_a')]);

    expect(audio.loadedUrls, ['http://example.test/a']);
    expect(player.isLoading.value, isFalse);
    expect(player.usingTtsFallback.value, isFalse);

    await player.play();
    expect(
      audio.loadedUrls,
      hasLength(1),
      reason: 'Play must reuse the already-buffered clip',
    );
    expect(audio.seeks, 1);
  });

  test('a stale clip preload cannot replace the next page audio', () async {
    final audio = _DelayedAudioPlayer();
    final player = NarrationPlayer(
      filePlayer: audio,
      tts: _StubTts(),
      resolver: _FixedResolver(),
    );
    addTearDown(player.dispose);

    final oldLoad = player.load([_seg('a', audioAssetId: 'aud_a')]);
    await audio.firstStarted.future;
    final newLoad = player.load([_seg('b', audioAssetId: 'aud_b')]);
    await Future<void>.delayed(Duration.zero);
    expect(audio.loadedUrls, ['http://example.test/a']);

    audio.finishFirst.complete();
    await Future.wait([oldLoad, newLoad]);
    expect(audio.loadedUrls, [
      'http://example.test/a',
      'http://example.test/b',
    ]);
    await player.play();
    expect(audio.loadedUrls, hasLength(2));
  });

  test('authored stories receive the HTTP-backed fetcher', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            dio: Dio(BaseOptions(baseUrl: 'http://localhost')),
            store: store,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(narrationAudioFetcherProvider('story-1')),
      isA<TtsNarrationAudioFetcher>(),
    );
  });
}

/// A fetcher whose per-segment completion the test drives by hand.
class _ControllableFetcher implements NarrationAudioFetcher {
  final _pending = <String, Completer<String?>>{};

  void complete(String segmentId, String? path) {
    _pending.putIfAbsent(segmentId, Completer<String?>.new);
    if (!_pending[segmentId]!.isCompleted) _pending[segmentId]!.complete(path);
  }

  @override
  Future<String?> pathFor(NarrationSegment segment) {
    return _pending.putIfAbsent(segment.id, Completer<String?>.new).future;
  }

  @override
  Future<void> dispose() async {}
}

class _FixedResolver implements AssetUrlResolver {
  @override
  Future<Map<String, String>> resolve(List<String> assetIds) async => {
    for (final id in assetIds)
      id: 'http://example.test/${id.substring('aud_'.length)}',
  };
}

/// Overrides everything [NarrationPlayer] touches so no real platform call is
/// made. The superclass constructor still runs, hence ensureInitialized above.
class _StubAudioPlayer extends AudioPlayer {
  final List<String> loadedUrls = [];
  int seeks = 0;

  @override
  Stream<bool> get playingStream => Stream.value(true);

  @override
  Stream<ProcessingState> get processingStateStream =>
      Stream.value(ProcessingState.completed);

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loadedUrls.add(url);
    return Duration.zero;
  }

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async => Duration.zero;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks++;
  }

  @override
  Future<void> dispose() async {}
}

class _DelayedAudioPlayer extends _StubAudioPlayer {
  final firstStarted = Completer<void>();
  final finishFirst = Completer<void>();

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loadedUrls.add(url);
    if (!firstStarted.isCompleted) {
      firstStarted.complete();
      await finishFirst.future;
    }
    return Duration.zero;
  }
}

class _StubTts extends FlutterTts {
  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 1;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;
}
