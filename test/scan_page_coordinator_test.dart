import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/line_audio_player.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/page_validation_client.dart';
import 'package:storybook_ar/features/scan_any_page/scan_page_coordinator.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

class FakeScanner implements ScanService {
  int calls = 0;
  @override
  Future<ScannedPage> scanAndRecognize() async {
    calls++;
    return ScannedPage(Uint8List.fromList([1]), 100, 100, const [
      ScannedLine('Tiếng Việt', .1, .1, .8, .1),
    ]);
  }
}

class FakeClient implements PageReadingClient {
  int validations = 0, audioCalls = 0;
  String? validationError, audioError, blockedReason;
  Completer<List<File>>? pendingAudio;
  Completer<PageValidationResult>? pendingValidation;
  CancelToken? token;
  final languages = <String?>[];
  final operations = <String?>[];
  String? exactText;
  @override
  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    validations++;
    token = cancelToken;
    languages.add(contentLanguage);
    operations.add(operationId);
    exactText = page.lines.single.text;
    if (validationError != null) throw PageRequestFailure(validationError!);
    if (pendingValidation != null) return pendingValidation!.future;
    if (blockedReason != null) {
      return PageValidationResult.blocked(blockedReason);
    }
    return const PageValidationResult.approved('proof');
  }

  @override
  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    audioCalls++;
    token = cancelToken;
    languages.add(contentLanguage);
    operations.add(operationId);
    expect(lines.single, exactText);
    if (audioError != null) throw PageRequestFailure(audioError!);
    if (pendingAudio != null) return pendingAudio!.future;
    return [File('nonexistent-test-clip')];
  }

  @override
  Future<void> dispose() async {}
}

class FakePlayer implements ScanPagePlayer {
  @override
  final currentLine = ValueNotifier(0);
  @override
  final completed = ValueNotifier(false);
  @override
  final playing = ValueNotifier(false);
  int loads = 0;
  Completer<void>? pendingLoad;
  final playCompletion = Completer<void>();
  @override
  Future<void> load(List<File> clips) async {
    loads++;
    if (pendingLoad != null) await pendingLoad!.future;
  }

  @override
  Future<void> play() {
    playing.value = true;
    return playCompletion.future;
  }

  @override
  Future<void> pause() async {
    playing.value = false;
  }

  @override
  Future<void> resume() => play();
  @override
  Future<void> replay() => play();
  @override
  Future<void> stop() async {
    playing.value = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeScanner scanner;
  late FakeClient client;
  late FakePlayer player;
  late ScanPageCoordinator session;
  setUp(() {
    scanner = FakeScanner();
    client = FakeClient();
    player = FakePlayer();
    session = ScanPageCoordinator(
      scanner: scanner,
      client: client,
      player: player,
    )..bindPlayback();
  });
  tearDown(() async {
    await session.close();
    session.dispose();
  });

  test(
    'validation retry keeps capture and normalized Vietnamese strings',
    () async {
      client.validationError = 'provider_timeout';
      await session.scan('profile', language: 'vi');
      expect(session.phase, ScanPagePhase.failed);
      expect(session.page, isNull);
      expect(session.recovery, ScanRecovery.validation);
      expect(client.audioCalls, 0);
      client.validationError = null;
      await session.retry();
      expect(scanner.calls, 1);
      expect(client.validations, 2);
      expect(client.exactText, 'Tiếng Việt');
      expect(client.languages, everyElement('vi'));
      expect(client.operations.toSet().length, 3);
      expect(session.phase, ScanPagePhase.ready);
    },
  );

  test('audio retry skips capture/validation; expiry revalidates', () async {
    client.audioError = 'provider_timeout';
    await session.scan('profile', language: 'en');
    expect(session.page, isNotNull);
    expect(session.recovery, ScanRecovery.audio);
    client.audioError = 'page_approval_expired';
    await session.retry();
    expect(client.validations, 1);
    expect(session.recovery, ScanRecovery.validation);
    expect(session.page, isNull);
    client.audioError = null;
    await session.retry();
    expect(scanner.calls, 1);
    expect(client.validations, 2);
    expect(client.languages, everyElement('en'));
    expect(session.phase, ScanPagePhase.ready);
  });

  test('blocked or invalid approval cannot enable playback', () async {
    client.blockedReason = 'content_unsuitable';
    await session.scan('profile');
    expect(session.phase, ScanPagePhase.blocked);
    expect(client.audioCalls, 0);
    expect(session.page, isNull);
    client.blockedReason = null;
    client.audioError = 'page_approval_invalid';
    await session.scan('profile');
    expect(session.recovery, ScanRecovery.retake);
    expect(session.page, isNull);
    await session.retry();
    expect(client.audioCalls, 1);
  });

  test('playing/pause become available before play Future completes', () async {
    await session.scan('profile');
    await session.listen();
    expect(player.playCompletion.isCompleted, false);
    expect(session.phase, ScanPagePhase.playing);
    await session.pause();
    expect(session.phase, ScanPagePhase.paused);
    player.completed.value = true;
    expect(session.phase, ScanPagePhase.completed);
  });

  test(
    'exit cancels requests and removes files returned by stale response',
    () async {
      client.pendingAudio = Completer<List<File>>();
      final scan = session.scan('profile');
      while (client.audioCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(session.phase, ScanPagePhase.preparingAudio);
      final token = client.token!;
      await session.close();
      expect(token.isCancelled, true);
      final directory = await Directory.systemTemp.createTemp(
        'stale-page-test',
      );
      final clip = await File('${directory.path}/000.mp3').writeAsBytes([1]);
      client.pendingAudio!.complete([clip]);
      await scan;
      expect(clip.existsSync(), false);
      expect(player.loads, 0);
      expect(session.page, isNull);
      await directory.delete();
    },
  );
  test(
    'new scan cancels validation and stale approval cannot generate audio',
    () async {
      final pending = Completer<PageValidationResult>();
      client.pendingValidation = pending;
      final firstScan = session.scan('profile', language: 'vi');
      while (client.validations == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final token = client.token!;
      client.pendingValidation = null;
      await session.scan('profile', language: 'en');
      expect(token.isCancelled, true);
      expect(session.phase, ScanPagePhase.ready);
      pending.complete(const PageValidationResult.approved('stale-proof'));
      await firstScan;
      expect(client.audioCalls, 1);
      expect(session.contentLanguage, 'en');
      expect(session.phase, ScanPagePhase.ready);
    },
  );

  test('exit during player load cannot restore ready or leave clips', () async {
    final pending = Completer<void>();
    player.pendingLoad = pending;
    final scan = session.scan('profile');
    while (player.loads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final closing = session.close();
    pending.complete();
    await scan;
    await closing;
    expect(session.phase, ScanPagePhase.setup);
    expect(session.page, isNull);
  });
}
