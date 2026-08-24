import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/ar/ar_reader_controller.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';

class _FakeResolver implements AssetUrlResolver {
  @override
  Future<Map<String, String>> resolve(List<String> ids) async => const {};
}

class _FakeDownloader implements ArAudioDownloader {
  @override
  Future<List<int>> download(String url) async => const [1];
}

class _FakeTts implements TtsFileSynthesizer {
  _FakeTts({this.succeeds = true});

  final bool succeeds;

  @override
  String get fileExtension => 'wav';

  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    if (!succeeds) return false;
    await File(filePath).writeAsBytes([1]);
    return true;
  }
}

class _FakeReader implements StoryReader {
  _FakeReader({this.supported = true, this.failureCode});

  final bool supported;
  final String? failureCode;

  int openCalls = 0;
  List<ArNarrationPage>? openedWith;
  int? openedAtIndex;
  ArCharacter? openedWithCharacter;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
  }) async {
    openCalls++;
    openedWith = pages;
    openedAtIndex = initialPageIndex;
    openedWithCharacter = character;
    if (failureCode != null) throw StoryReaderFailure(failureCode!);
    return const StoryReaderResult(
      terminalCode: 'completed',
      lastPageId: 'p1',
      pagesRead: ['p1'],
    );
  }
}

StoryDetail _detail() => StoryDetail(
      story: const Story(id: 'story-1', title: 'T', slug: 's'),
      pages: const [
        StoryPage(id: 'p1', storyId: 'story-1', pageNumber: 1),
        StoryPage(id: 'p2', storyId: 'story-1', pageNumber: 2),
      ],
      segments: const [
        NarrationSegment(
          id: 's1',
          storyId: 'story-1',
          pageId: 'p1',
          speakerKey: 'narrator',
          text: 'one',
          voiceId: 'v',
          sortOrder: 0,
        ),
        NarrationSegment(
          id: 's2',
          storyId: 'story-1',
          pageId: 'p2',
          speakerKey: 'narrator',
          text: 'two',
          voiceId: 'v',
          sortOrder: 0,
        ),
      ],
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ar_controller_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  ArReaderController build({
    required StoryReader reader,
    bool ttsSucceeds = true,
    int initialPageIndex = 0,
    ArCharacter character = const ArCharacter(
      id: 'fox_default',
      displayName: 'Fox',
      assetBaseName: 'scan_any_page_character',
    ),
  }) =>
      ArReaderController(
        detail: _detail(),
        reader: reader,
        character: character,
        resolver: _FakeResolver(),
        fetcher: null,
        tts: _FakeTts(succeeds: ttsSucceeds),
        downloader: _FakeDownloader(),
        directory: dir,
        initialPageIndex: initialPageIndex,
      );

  test('walks through checkingSupport, preparing, opening, reading', () async {
    final reader = _FakeReader();
    final controller = build(reader: reader);
    final phases = <ArReaderPhase>[];
    controller.addListener(() => phases.add(controller.value.phase));

    final result = await controller.start();

    expect(phases, [
      ArReaderPhase.checkingSupport,
      ArReaderPhase.preparing,
      // one progress tick per segment
      ArReaderPhase.preparing,
      ArReaderPhase.preparing,
      ArReaderPhase.opening,
      ArReaderPhase.reading,
    ]);
    expect(result?.terminalCode, 'completed');
    expect(controller.value.result?.lastPageId, 'p1');
  });

  test('reports preparation progress', () async {
    final controller = build(reader: _FakeReader());
    final seen = <String>[];
    controller.addListener(() {
      if (controller.value.phase == ArReaderPhase.preparing) {
        seen.add('${controller.value.prepared}/${controller.value.total}');
      }
    });

    await controller.start();

    expect(seen, ['0/0', '1/2', '2/2']);
  });

  test('fails as ar_unsupported without preparing anything', () async {
    final reader = _FakeReader(supported: false);
    final controller = build(reader: reader);

    final result = await controller.start();

    expect(result, isNull);
    expect(controller.value.phase, ArReaderPhase.failure);
    expect(controller.value.failureCode, 'ar_unsupported');
    expect(reader.openCalls, 0);
    // Nothing should have been written for a device that cannot show AR.
    expect(dir.listSync(), isEmpty);
  });

  test('fails as narration_unavailable and never opens the reader', () async {
    final reader = _FakeReader();
    final controller = build(reader: reader, ttsSucceeds: false);

    final result = await controller.start();

    expect(result, isNull);
    expect(controller.value.phase, ArReaderPhase.failure);
    expect(controller.value.failureCode, 'narration_unavailable');
    expect(reader.openCalls, 0);
  });

  test('surfaces a reader failure code', () async {
    final controller =
        build(reader: _FakeReader(failureCode: 'model_missing'));

    final result = await controller.start();

    expect(result, isNull);
    expect(controller.value.phase, ArReaderPhase.failure);
    expect(controller.value.failureCode, 'model_missing');
  });

  test('passes the initial page index through to the reader', () async {
    final reader = _FakeReader();
    final controller = build(reader: reader, initialPageIndex: 1);

    await controller.start();

    expect(reader.openedAtIndex, 1);
    expect(reader.openedWith?.map((p) => p.pageId), ['p1', 'p2']);
  });

  test('passes the selected character through to the reader', () async {
    final reader = _FakeReader();
    const doll = ArCharacter(
      id: 'cute_doll_v02',
      displayName: 'Doll 2',
      assetBaseName: 'cute_doll_v02',
    );

    await build(reader: reader, character: doll).start();

    expect(reader.openedWithCharacter, same(doll));
  });

  test('a second start while busy is a no-op', () async {
    final reader = _FakeReader();
    final controller = build(reader: reader);

    final first = controller.start();
    final second = controller.start();

    await first;
    expect(await second, isNull);
    expect(reader.openCalls, 1);
  });
}
