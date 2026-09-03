import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/player/narration_audio_fetcher.dart';

class _FakeResolver implements AssetUrlResolver {
  _FakeResolver(this.urls);

  final Map<String, String> urls;

  @override
  Future<Map<String, String>> resolve(List<String> ids) async => {
        for (final id in ids)
          if (urls.containsKey(id)) id: urls[id]!,
      };
}

class _FakeDownloader implements ArAudioDownloader {
  _FakeDownloader({this.throws = false});

  final bool throws;
  final downloaded = <String>[];

  @override
  Future<List<int>> download(String url) async {
    if (throws) throw const SocketException('offline');
    downloaded.add(url);
    return [1, 2, 3];
  }
}

class _FakeTts implements TtsFileSynthesizer {
  _FakeTts({this.succeeds = true});

  final bool succeeds;
  final synthesized = <String>[];

  @override
  String get fileExtension => 'wav';

  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    if (!succeeds) return false;
    synthesized.add(text);
    await File(filePath).writeAsBytes([9]);
    return true;
  }
}

class _FakeFetcher implements NarrationAudioFetcher {
  _FakeFetcher(this.directory);

  final Directory directory;
  final requested = <String>[];

  @override
  Future<String?> pathFor(NarrationSegment segment) async {
    requested.add(segment.id);
    final file = File('${directory.path}/narration_${segment.id}.mp3');
    await file.writeAsBytes([7, 7]);
    return file.path;
  }

  @override
  Future<void> dispose() async {}
}

NarrationSegment _segment({
  required String id,
  required String pageId,
  required int sortOrder,
  String? assetId,
  String text = 'hello',
}) =>
    NarrationSegment(
      id: id,
      storyId: 'story-1',
      pageId: pageId,
      speakerKey: 'narrator',
      text: text,
      voiceId: 'v1',
      audioAssetId: assetId,
      sortOrder: sortOrder,
    );

StoryDetail _detail({
  required List<StoryPage> pages,
  required List<NarrationSegment> segments,
}) =>
    StoryDetail(
      // id/title/slug are the only required fields; everything else defaults.
      // `contentStatus` is a ContentStatus enum, not a String - do not pass one.
      story: const Story(id: 'story-1', title: 'T', slug: 's'),
      pages: pages,
      segments: segments,
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ar_bundle_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('builds a file name that is story-scoped and uses page/sort numbers', () {
    expect(
      arSegmentFileName(
        storyId: 'ab-cd-ef',
        pageNumber: 2,
        sortOrder: 1,
        extension: 'mp3',
      ),
      'ar_abcdef_p2_s1.mp3',
    );
  });

  test('keeps every segment of a multi-segment page', () async {
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0, assetId: 'a1'),
        _segment(id: 's2', pageId: 'p1', sortOrder: 1, assetId: 'a2'),
        _segment(id: 's3', pageId: 'p1', sortOrder: 2, assetId: 'a3'),
      ],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver({'a1': 'u1', 'a2': 'u2', 'a3': 'u3'}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(pages, hasLength(1));
    expect(pages.single.audioFilePaths, hasLength(3));
    expect(
      pages.single.audioFilePaths.map((p) => p.split('/').last),
      ['ar_story1_p1_s0.mp3', 'ar_story1_p1_s1.mp3', 'ar_story1_p1_s2.mp3'],
    );
  });

  test('copies the fetcher clip instead of renaming it', () async {
    final fetcher = _FakeFetcher(dir);
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: fetcher,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    // The fetcher's own file must survive - the player still holds this path.
    expect(File('${dir.path}/narration_s1.mp3').existsSync(), isTrue);
    expect(File('${dir.path}/ar_story1_p1_s0.mp3').existsSync(), isTrue);
  });

  test('falls back to device TTS when nothing else resolves', () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0, text: 'spoken')],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(tts.synthesized, ['spoken']);
    expect(pages.single.audioFilePaths.single, endsWith('ar_story1_p1_s0.wav'));
  });

  test('with no fetcher (cloud disabled) every segment still synthesizes',
      () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0, text: 'first'),
        _segment(id: 's2', pageId: 'p1', sortOrder: 1, text: 'second'),
      ],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(tts.synthesized, ['first', 'second']);
    expect(pages.single.audioFilePaths, hasLength(2));
  });

  test('falls back to device TTS when the download fails', () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0, assetId: 'a1', text: 'x'),
      ],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver({'a1': 'u1'}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(throws: true),
      directory: dir,
    );

    expect(tts.synthesized, ['x']);
    expect(pages.single.audioFilePaths.single, endsWith('.wav'));
  });

  test('synthesizes from page text when a page has no segments', () async {
    final tts = _FakeTts();
    final detail = _detail(
      pages: [
        const StoryPage(
          id: 'p1',
          storyId: 'story-1',
          pageNumber: 1,
          pageText: 'page words',
        ),
      ],
      segments: const [],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: tts,
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(tts.synthesized, ['page words']);
    expect(pages.single.audioFilePaths, hasLength(1));
  });

  test('fails the whole bundle when one segment cannot be prepared', () async {
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );

    expect(
      () => prepareArNarration(
        detail: detail,
        resolver: _FakeResolver(const {}),
        fetcher: null,
        tts: _FakeTts(succeeds: false),
        downloader: _FakeDownloader(),
        directory: dir,
      ),
      throwsA(isA<ArNarrationFailure>()
          .having((e) => e.code, 'code', 'narration_unavailable')),
    );
  });

  test('deletes stale clips for this story before preparing', () async {
    final stale = File('${dir.path}/ar_story1_p9_s0.mp3')
      ..writeAsBytesSync([0]);
    final other = File('${dir.path}/ar_other_p1_s0.mp3')..writeAsBytesSync([0]);
    final detail = _detail(
      pages: [const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1)],
      segments: [_segment(id: 's1', pageId: 'p1', sortOrder: 0)],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(stale.existsSync(), isFalse, reason: 'stale clip for this story');
    expect(other.existsSync(), isTrue, reason: 'another story must be untouched');
  });

  test('reports progress once per segment', () async {
    final seen = <String>[];
    final detail = _detail(
      pages: [
        const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1),
        const StoryPage(id: 'p2', storyId: 'story-1', pageNumber: 2),
      ],
      segments: [
        _segment(id: 's1', pageId: 'p1', sortOrder: 0),
        _segment(id: 's2', pageId: 'p1', sortOrder: 1),
        _segment(id: 's3', pageId: 'p2', sortOrder: 0),
      ],
    );
    await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
      onProgress: (done, total) => seen.add('$done/$total'),
    );

    expect(seen, ['1/3', '2/3', '3/3']);
  });

  test('orders pages by page number, not by list order', () async {
    final detail = _detail(
      pages: [
        const StoryPage(id: 'p2', storyId: 'story-1', pageNumber: 2),
        const StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1),
      ],
      segments: [
        _segment(id: 's2', pageId: 'p2', sortOrder: 0),
        _segment(id: 's1', pageId: 'p1', sortOrder: 0),
      ],
    );
    final pages = await prepareArNarration(
      detail: detail,
      resolver: _FakeResolver(const {}),
      fetcher: null,
      tts: _FakeTts(),
      downloader: _FakeDownloader(),
      directory: dir,
    );

    expect(pages.map((p) => p.pageId), ['p1', 'p2']);
    expect(pages.map((p) => p.pageNumber), [1, 2]);
  });

  test('serialises to the native wire shape', () {
    const page = ArNarrationPage(
      pageId: 'p1',
      pageNumber: 3,
      audioFilePaths: ['/a.mp3', '/b.wav'],
    );

    expect(page.toJson(), {
      'pageId': 'p1',
      'pageNumber': 3,
      'audioFilePaths': ['/a.mp3', '/b.wav'],
    });
  });
}
