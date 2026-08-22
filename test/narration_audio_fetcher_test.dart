import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/player/narration_audio_fetcher.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

class _FakeTtsClient implements TtsClient {
  _FakeTtsClient({this.failure});

  final TtsGenerationFailure? failure;
  final calls = <String>[];
  final pending = <Completer<File>>[];
  var disposed = false;

  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    calls.add(fileName ?? 'default');
    if (failure != null) return Future.error(failure!);
    final completer = Completer<File>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

NarrationSegment _segment(String id, String text) => NarrationSegment(
      id: id,
      storyId: 's',
      pageId: 'p',
      speakerKey: 'narrator',
      text: text,
      voiceId: 'coral',
      sortOrder: 0,
    );

void main() {
  test('fetches once per segment and caches the result', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'hello'));
    client.pending.single.complete(File('/tmp/seg1.mp3'));
    expect(await first, '/tmp/seg1.mp3');

    expect(await fetcher.pathFor(_segment('seg1', 'hello')), '/tmp/seg1.mp3');
    expect(client.calls, hasLength(1));
  });

  test('a second request while the first is in flight reuses the same future',
      () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'hello'));
    final second = fetcher.pathFor(_segment('seg1', 'hello'));
    expect(client.calls, hasLength(1));

    client.pending.single.complete(File('/tmp/seg1.mp3'));
    expect(await first, '/tmp/seg1.mp3');
    expect(await second, '/tmp/seg1.mp3');
  });

  test('returns null on generation failure and keeps it retryable', () async {
    final client =
        _FakeTtsClient(failure: const TtsGenerationFailure('timeout'));
    final fetcher = TtsNarrationAudioFetcher(client);

    expect(await fetcher.pathFor(_segment('seg1', 'hello')), isNull);
    expect(await fetcher.pathFor(_segment('seg1', 'hello')), isNull);
    expect(client.calls, hasLength(2), reason: 'a failure must stay retryable');
  });

  test('uses a distinct file name per segment', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    fetcher.pathFor(_segment('seg1', 'a'));
    fetcher.pathFor(_segment('seg2', 'b'));

    expect(client.calls, ['narration_seg1.mp3', 'narration_seg2.mp3']);
  });

  test('dispose clears the cache and disposes the client', () async {
    final client = _FakeTtsClient();
    final fetcher = TtsNarrationAudioFetcher(client);

    final first = fetcher.pathFor(_segment('seg1', 'a'));
    client.pending.single.complete(File('/tmp/seg1.mp3'));
    await first;
    await fetcher.dispose();

    expect(client.disposed, isTrue);
    fetcher.pathFor(_segment('seg1', 'a'));
    expect(client.calls, hasLength(2),
        reason: 'the cache must not survive dispose');
  });
}
