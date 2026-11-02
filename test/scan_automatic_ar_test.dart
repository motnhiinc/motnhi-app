import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';
import 'package:storybook_ar/features/scan_any_page/page_validation_client.dart';
import 'package:storybook_ar/features/scan_any_page/scan_page_coordinator.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

import 'helpers/scan_ar_fakes.dart';

class _DelayedClient extends ArTestClient {
  _DelayedClient(super.directory);
  final validation = Completer<PageValidationResult>();
  CancelToken? token;
  bool failAudioOnce = false;

  @override
  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) {
    if (failAudioOnce) {
      failAudioOnce = false;
      audioCalls++;
      return Future.error(const PageRequestFailure('provider_timeout'));
    }
    return super.prepareAudio(
      proof,
      profileId,
      lines,
      contentLanguage: contentLanguage,
      cancelToken: cancelToken,
      attemptId: attemptId,
      operationId: operationId,
    );
  }

  @override
  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) {
    validations++;
    token = cancelToken;
    return validation.future;
  }
}

class _PreparingReader implements PreparingStoryReader {
  final opened = Completer<void>();
  final attached = Completer<void>();
  var returned = Completer<StoryReaderResult>();
  List<String> paths = [];
  String? id;
  int closes = 0;
  int opens = 0;
  bool failOpen = false;
  bool failAttach = false;

  @override
  Future<StoryReaderResult> openPreparing({
    required String sessionId,
    required ArCharacter character,
  }) {
    id = sessionId;
    opens++;
    if (returned.isCompleted) returned = Completer<StoryReaderResult>();
    if (!opened.isCompleted) opened.complete();
    if (failOpen) return Future.error(const StoryReaderFailure('ar_failed'));
    return returned.future;
  }

  @override
  Future<void> attachNarration({
    required String sessionId,
    required List<ArNarrationPage> pages,
  }) async {
    expect(sessionId, id);
    if (failAttach) throw const StoryReaderFailure('audio_failed');
    paths = pages.single.audioFilePaths;
    expect(paths.every((path) => File(path).existsSync()), isTrue);
    if (!attached.isCompleted) attached.complete();
  }

  void exit([String code = 'cancelled']) {
    if (!returned.isCompleted) {
      returned.complete(
        StoryReaderResult(
          terminalCode: code,
          lastPageId: null,
          pagesRead: const [],
        ),
      );
    }
  }

  @override
  Future<void> closePreparing(String sessionId) async {
    expect(sessionId, id);
    closes++;
    exit();
  }
}

void main() {
  late Directory directory;
  late _DelayedClient client;
  late _PreparingReader reader;
  late ArTestPlayer player;
  late ScanPageCoordinator session;
  late ScanArEntry entry;
  var cancelled = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('automatic-ar-');
    client = _DelayedClient(directory);
    reader = _PreparingReader();
    player = ArTestPlayer();
    cancelled = 0;
    session = ScanPageCoordinator(
      scanner: ArTestScanner(),
      client: client,
      player: player,
      onCancelled: () => cancelled++,
    )..bindPlayback();
    entry = ScanArEntry(
      reader: reader,
      character: dinosaurCharacter,
      temporaryDirectory: () async => directory,
    );
  });
  tearDown(() async {
    await session.close();
    session.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'opens placement before validation/audio, attaches approved clips once',
    () async {
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      expect(session.arBusy, isTrue);
      expect(client.audioCalls, 0);
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      await reader.attached.future;
      expect(client.audioCalls, 1);
      expect(player.plays, 0);
      expect(reader.paths.length, 2);
      reader.exit();
      await settle();
      expect(reader.paths.every((path) => !File(path).existsSync()), isTrue);
      expect(client.files.every((file) => file.existsSync()), isTrue);
    },
  );

  test(
    'blocked page dismisses AR without preparing or playing audio',
    () async {
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      client.validation.complete(
        const PageValidationResult.blocked('content_unsuitable'),
      );
      await scanning;
      await settle();
      expect(reader.closes, 1);
      expect(client.audioCalls, 0);
      expect(player.plays, 0);
      expect(session.phase, ScanPagePhase.blocked);
      expect(cancelled, 0);
    },
  );

  test(
    'early Close cancels requests and prevents stale audio delivery',
    () async {
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      reader.exit();
      await settle();
      expect(cancelled, 1);
      expect(client.token!.isCancelled, isTrue);
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      expect(client.audioCalls, 0);
      expect(player.plays, 0);
    },
  );

  test(
    'Listen without AR continues processing and autoplays once ready',
    () async {
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      reader.exit('listen_without_ar');
      await settle();
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      expect(player.plays, 1);
      expect(cancelled, 0);
      expect(reader.paths, isEmpty);
    },
  );

  test('AR open failure degrades to audio without a second request', () async {
    reader.failOpen = true;
    final scanning = session.scan('profile', automaticAr: entry);
    await reader.opened.future;
    await settle();
    client.validation.complete(const PageValidationResult.approved('proof'));
    await scanning;
    expect(player.plays, 1);
    expect(client.audioCalls, 1);
    expect(session.arFailure, 'ar_failed');
  });

  test(
    'attach failure closes native reader and retains audio fallback',
    () async {
      reader.failAttach = true;
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      await settle();
      expect(reader.closes, 1);
      expect(player.plays, 1);
      expect(client.audioCalls, 1);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'route disposal closes native session without waiting for user',
    () async {
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      await session.close();
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      expect(reader.closes, 1);
      expect(client.audioCalls, 0);
      expect(player.plays, 0);
    },
  );

  test('AR-disabled flow plays approved audio automatically', () async {
    final scanning = session.scan('profile', autoplayWithoutAr: true);
    await settle();
    client.validation.complete(const PageValidationResult.approved('proof'));
    await scanning;
    expect(player.plays, 1);
    expect(reader.id, isNull);
  });

  test(
    'audio retry reopens placement but reuses validation and capture',
    () async {
      client.failAudioOnce = true;
      final scanning = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      expect(session.phase, ScanPagePhase.failed);
      await session.retry();
      expect(reader.opens, 2);
      expect(client.validations, 1);
      expect(client.audioCalls, 2);
      expect(reader.paths.length, 2);
      expect(player.plays, 0);
    },
  );

  test('background preparation never starts audio until foreground', () async {
    final scanning = session.scan('profile', autoplayWithoutAr: true);
    await settle();
    session.setForeground(false);
    client.validation.complete(const PageValidationResult.approved('proof'));
    await scanning;
    expect(player.plays, 0);
    session.setForeground(true);
    await settle();
    expect(player.plays, 1);
    session.setForeground(false);
    await settle();
    expect(player.playing.value, isFalse);
    session.setForeground(true);
    await settle();
    expect(player.plays, 1); // Returning never resumes a paused narration.
  });

  test(
    'rescan closes pending placement and ignores the old validation',
    () async {
      final first = session.scan('profile', automaticAr: entry);
      await reader.opened.future;
      final second = session.scan('profile', language: 'en');
      await settle();
      client.validation.complete(const PageValidationResult.approved('proof'));
      await Future.wait([first, second]);
      expect(reader.closes, 1);
      expect(reader.paths, isEmpty);
      expect(client.audioCalls, 1);
      expect(session.contentLanguage, 'en');
      expect(cancelled, 0);
    },
  );

  test(
    'Scan next page releases old AR copies before starting new capture',
    () async {
      Future<void>? next;
      final nextEntry = ScanArEntry(
        reader: reader,
        character: dinosaurCharacter,
        temporaryDirectory: () async => directory,
        onScanNextPage: () {
          expect(
            reader.paths.every((path) => !File(path).existsSync()),
            isTrue,
          );
          next = session.scan('profile');
        },
      );
      final scanning = session.scan('profile', automaticAr: nextEntry);
      await reader.opened.future;
      client.validation.complete(const PageValidationResult.approved('proof'));
      await scanning;
      reader.exit('scan_next_page');
      await settle();
      expect(next, isNotNull);
      await next;
      expect(client.audioCalls, 2);
      expect(session.phase, ScanPagePhase.ready);
    },
  );
}
