import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';
import 'package:storybook_ar/features/scan_any_page/scan_page_coordinator.dart';
import 'helpers/scan_ar_fakes.dart';

void main() {
  late Directory directory;
  late ArTestClient client;
  late ArTestPlayer player;
  late ArTestReader reader;
  late ScanPageCoordinator session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scan-ar-test-');
    client = ArTestClient(directory);
    player = ArTestPlayer();
    reader = ArTestReader();
    session = ScanPageCoordinator(
      scanner: ArTestScanner(),
      client: client,
      player: player,
    )..bindPlayback();
  });
  tearDown(() async {
    await session.close();
    session.dispose();
    await directory.delete(recursive: true);
  });
  Future<StoryReaderResult?> open() => session.openAr(
    reader: reader,
    character: arCharacters.first,
    temporaryDirectory: () async => directory,
  );

  test(
    'approved scan opens one native page with ordered, allowed local clips',
    () async {
      await session.scan('profile');
      final result = await open();
      expect(result!.terminalCode, 'cancelled');
      expect(reader.opens, 1);
      expect(reader.character, same(arCharacters.first));
      expect(reader.heardBytes, [
        [1, 2, 3],
        [2, 2, 3],
      ]);
      for (final path in reader.pages.single.audioFilePaths) {
        expect(
          path,
          matches(r'/scan-ar-[^/]+/ar_[A-Za-z0-9]{32}_p1_s\d+\.mp3$'),
        );
        expect(File(path).existsSync(), isFalse);
      }
      expect(client.files.every((file) => file.existsSync()), isTrue);
      expect(client.validations, 1);
      expect(client.audioCalls, 1);
      expect(session.phase, ScanPagePhase.ready);
      await session.listen();
      expect(player.plays, 1);
    },
  );

  test('unapproved and blocked pages never enter AR', () async {
    expect(await open(), isNull);
    client.blocked = true;
    await session.scan('profile');
    expect(await open(), isNull);
    expect(reader.opens, 0);
    expect(client.audioCalls, 0);
  });

  test(
    'unsupported devices keep original audio and do not create AR files',
    () async {
      await session.scan('profile');
      reader.supported = false;
      await expectLater(
        open(),
        throwsA(
          isA<StoryReaderFailure>().having(
            (error) => error.code,
            'code',
            'ar_unsupported',
          ),
        ),
      );
      expect(reader.opens, 0);
      expect(session.arBusy, isFalse);
      expect(session.canOpenAr, isTrue);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
      await session.listen();
      expect(player.plays, 1);
    },
  );

  test(
    'native failure cleans copies, preserves Listen and allows retry',
    () async {
      await session.scan('profile');
      reader.failure = 'model_load_failed';
      await expectLater(open(), throwsA(isA<StoryReaderFailure>()));
      expect(session.canOpenAr, isTrue);
      expect(client.files.every((file) => file.existsSync()), isTrue);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
      reader.failure = null;
      await open();
      expect(reader.opens, 2);
      expect(client.audioCalls, 1);
    },
  );

  test(
    'AR pauses Listen, rejects duplicate opens and concurrent playback',
    () async {
      await session.scan('profile');
      await session.listen();
      reader.openPending = Completer<StoryReaderResult>();
      final pending = open();
      await reader.opened.future;
      expect(player.playing.value, isFalse);
      expect(session.phase, ScanPagePhase.paused);
      expect(session.arBusy, isTrue);
      expect(await open(), isNull);
      await session.listen();
      session.resume();
      session.replay();
      expect(player.plays, 1);
      reader.openPending!.complete(
        const StoryReaderResult(
          terminalCode: 'completed',
          lastPageId: null,
          pagesRead: [],
        ),
      );
      await pending;
      expect(session.arBusy, isFalse);
      session.resume();
      expect(player.plays, 2);
    },
  );

  test(
    'close during support probe prevents stale native presentation',
    () async {
      await session.scan('profile');
      reader.supportPending = Completer<StoryReaderSupport>();
      final pending = open();
      final closing = session.close();
      reader.supportPending!.complete(
        const StoryReaderSupport(supported: true),
      );
      expect(await pending, isNull);
      await closing;
      expect(reader.opens, 0);
      expect(client.files.every((file) => !file.existsSync()), isTrue);
    },
  );

  test('rescan during preparation cannot open the previous page', () async {
    await session.scan('profile');
    reader.supportPending = Completer<StoryReaderSupport>();
    final pending = open();
    final scanning = session.scan('profile', language: 'en');
    reader.supportPending!.complete(const StoryReaderSupport(supported: true));
    expect(await pending, isNull);
    await scanning;
    expect(reader.opens, 0);
    expect(session.phase, ScanPagePhase.ready);
    expect(client.audioCalls, 2);
  });

  test('cleanup waits for native playback before deleting its audio', () async {
    await session.scan('profile');
    reader.openPending = Completer<StoryReaderResult>();
    final pending = open();
    await reader.opened.future;
    final copied = reader.pages.single.audioFilePaths.map(File.new).toList();
    final closing = session.close();
    expect(copied.every((file) => file.existsSync()), isTrue);
    reader.openPending!.complete(
      const StoryReaderResult(
        terminalCode: 'cancelled',
        lastPageId: null,
        pagesRead: [],
      ),
    );
    await pending;
    await closing;
    expect(copied.every((file) => !file.existsSync()), isTrue);
  });

  test(
    'missing audio does not reach native reader or trigger fresh TTS',
    () async {
      await session.scan('profile');
      await client.files.last.delete();
      await expectLater(
        open(),
        throwsA(
          isA<StoryReaderFailure>().having(
            (error) => error.code,
            'code',
            'audio_missing',
          ),
        ),
      );
      expect(reader.opens, 0);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
      expect(client.audioCalls, 1);
    },
  );
}
