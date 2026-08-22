import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/native_character_reader.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/scan_any_page_controller.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

void main() {
  late _FakeScanService scanService;
  late _FakeTtsClient ttsClient;
  late _FakeCharacterReader characterReader;
  late ProviderContainer container;
  late NotifierProvider<ScanAnyPageController, ScanAnyPageState> provider;

  setUp(() {
    scanService = _FakeScanService();
    ttsClient = _FakeTtsClient();
    characterReader = _FakeCharacterReader();
    provider = NotifierProvider<ScanAnyPageController, ScanAnyPageState>(
      () => ScanAnyPageController(
        scanService: scanService,
        ttsClient: ttsClient,
        characterReader: characterReader,
      ),
    );
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  ScanAnyPageController controller() => container.read(provider.notifier);
  ScanAnyPageState state() => container.read(provider);

  test('starts idle then scans and reviews recognized text', () async {
    final scan = Completer<String>();
    scanService.results.add(scan.future);

    final operation = controller().startScan();
    expect(state(), const ScanAnyPageState(phase: ScanAnyPagePhase.scanning));

    scan.complete('Xin chao');
    await operation;

    expect(
      state(),
      const ScanAnyPageState(
        phase: ScanAnyPagePhase.reviewingText,
        recognizedText: 'Xin chao',
      ),
    );
  });

  test('scan cancellation returns to idle without failure', () async {
    scanService.results.add(Future.error(ScanCancelled()));

    await controller().startScan();

    expect(state(), const ScanAnyPageState());
  });

  test('scan failure exposes scan retry context and clears stale content',
      () async {
    scanService.results.add(Future.error(const ScanFailure('ocr_failed')));

    await controller().startScan();

    expect(
      state(),
      const ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'scan:ocr_failed',
      ),
    );
  });

  test('unexpected scan failure uses a stable scan retry code', () async {
    scanService.results.add(Future.error(StateError('broken')));

    await controller().startScan();

    expect(state().failureCode, 'scan:unknown');
  });

  test('confirmText rejects empty text without calling TTS', () async {
    await controller().confirmText('  ');

    expect(
      state(),
      const ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'tts:invalid_text',
      ),
    );
    expect(ttsClient.generatedTexts, isEmpty);
  });

  test('invalid confirm prevents an outstanding scan from overwriting failure',
      () async {
    final scan = Completer<String>();
    scanService.results.add(scan.future);
    final scanOperation = controller().startScan();

    await controller().confirmText('  ');
    scan.complete('stale OCR');
    await scanOperation;

    expect(state().phase, ScanAnyPagePhase.failure);
    expect(state().failureCode, 'tts:invalid_text');
    expect(state().recognizedText, isEmpty);
  });

  test('invalid confirm prevents an outstanding TTS from becoming ready',
      () async {
    final generation = Completer<File>();
    ttsClient.results.add(generation.future);
    final ttsOperation = controller().confirmText('Valid text');

    await controller().confirmText('  ');
    generation.complete(File('/tmp/stale.mp3'));
    await ttsOperation;

    expect(state().phase, ScanAnyPagePhase.failure);
    expect(state().failureCode, 'tts:invalid_text');
    expect(state().confirmedText, 'Valid text');
    expect(state().audioFile, isNull);
  });

  test('confirmText validates the limit by Unicode code points', () async {
    final character = String.fromCharCode(0x1F642);
    final file = File('/tmp/scan-any-page.mp3');
    ttsClient.results.add(Future.value(file));

    await controller().confirmText(character * 4000);

    expect(state().phase, ScanAnyPagePhase.readyForAr);
    expect(ttsClient.generatedTexts.single.runes.length, 4000);

    await controller().confirmText(character * 4001);

    expect(state().phase, ScanAnyPagePhase.failure);
    expect(state().failureCode, 'tts:invalid_text');
    expect(ttsClient.generatedTexts, hasLength(1));
  });

  test('TTS success trims and stores confirmed text and local audio', () async {
    final generation = Completer<File>();
    final file = File('/tmp/scan-any-page.mp3');
    ttsClient.results.add(generation.future);

    final operation = controller().confirmText('  Mot cau chuyen  ');
    expect(
      state(),
      const ScanAnyPageState(
        phase: ScanAnyPagePhase.generatingAudio,
        confirmedText: 'Mot cau chuyen',
      ),
    );

    generation.complete(file);
    await operation;

    expect(
      state(),
      ScanAnyPageState(
        phase: ScanAnyPagePhase.readyForAr,
        confirmedText: 'Mot cau chuyen',
        audioFile: file,
      ),
    );
  });

  test('TTS failure retains recognized and confirmed text for retry', () async {
    scanService.results.add(Future.value('OCR text'));
    await controller().startScan();
    ttsClient.results.add(
      Future.error(const TtsGenerationFailure('backend_unreachable')),
    );

    await controller().confirmText('Corrected text');

    expect(
      state(),
      const ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        recognizedText: 'OCR text',
        confirmedText: 'Corrected text',
        failureCode: 'tts:backend_unreachable',
      ),
    );

    final file = File('/tmp/retry.mp3');
    ttsClient.results.add(Future.value(file));
    await controller().retryTts();

    expect(scanService.callCount, 1);
    expect(ttsClient.generatedTexts, ['Corrected text', 'Corrected text']);
    expect(state().phase, ScanAnyPagePhase.readyForAr);
    expect(state().audioFile, same(file));
  });

  test('retryTts without confirmed text remains a TTS validation failure',
      () async {
    await controller().retryTts();

    expect(state().failureCode, 'tts:invalid_text');
    expect(ttsClient.generatedTexts, isEmpty);
  });

  test('AR completion and cancellation return to ready without regenerating',
      () async {
    final file = File('/tmp/narration.mp3');
    ttsClient.results.add(Future.value(file));
    await controller().confirmText('Read me');
    characterReader.results.add(Future.value());

    final completion = controller().openCharacterReader();
    expect(state().phase, ScanAnyPagePhase.openingAr);
    await completion;
    expect(state().phase, ScanAnyPagePhase.readyForAr);

    characterReader.results.add(Future.error(CharacterReaderCancelled()));
    await controller().openCharacterReader();

    expect(state().phase, ScanAnyPagePhase.readyForAr);
    expect(state().failureCode, isNull);
    expect(ttsClient.generatedTexts, ['Read me']);
    expect(characterReader.openedPaths, [file.path, file.path]);
  });

  test('AR failure retains audio and retries AR without retrying TTS',
      () async {
    final file = File('/tmp/narration.mp3');
    ttsClient.results.add(Future.value(file));
    await controller().confirmText('Read me');
    characterReader.results.add(
      Future.error(const CharacterReaderFailure('ar_unavailable')),
    );

    await controller().openCharacterReader();

    expect(
      state(),
      ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        confirmedText: 'Read me',
        audioFile: file,
        failureCode: 'ar:ar_unavailable',
      ),
    );

    characterReader.results.add(Future.value());
    await controller().openCharacterReader();

    expect(state().phase, ScanAnyPagePhase.readyForAr);
    expect(ttsClient.generatedTexts, ['Read me']);
    expect(characterReader.openedPaths, [file.path, file.path]);
  });

  test('opening AR without audio exposes AR retry context', () async {
    await controller().openCharacterReader();

    expect(state().failureCode, 'ar:missing_audio');
    expect(characterReader.openedPaths, isEmpty);
  });

  test('missing-audio open prevents an outstanding scan from overwriting it',
      () async {
    final scan = Completer<String>();
    scanService.results.add(scan.future);
    final scanOperation = controller().startScan();

    await controller().openCharacterReader();
    scan.complete('stale OCR');
    await scanOperation;

    expect(state().phase, ScanAnyPagePhase.failure);
    expect(state().failureCode, 'ar:missing_audio');
    expect(state().recognizedText, isEmpty);
  });

  test('reset disposes temporary audio and clears all state', () async {
    final file = File('/tmp/narration.mp3');
    ttsClient.results.add(Future.value(file));
    await controller().confirmText('Read me');

    await controller().reset();

    expect(ttsClient.disposeCount, 1);
    expect(state(), const ScanAnyPageState());
  });

  test('controller disposal invokes TtsClient.dispose', () async {
    controller();

    container.dispose();
    await pumpEventQueue();

    expect(ttsClient.disposeCount, 1);
  });

  test('late scan and TTS results cannot overwrite reset state', () async {
    final scan = Completer<String>();
    scanService.results.add(scan.future);
    final scanOperation = controller().startScan();
    await controller().reset();
    scan.complete('stale OCR');
    await scanOperation;
    expect(state(), const ScanAnyPageState());

    final generation = Completer<File>();
    ttsClient.results.add(generation.future);
    final ttsOperation = controller().confirmText('stale text');
    await controller().reset();
    generation.complete(File('/tmp/stale.mp3'));
    await ttsOperation;
    expect(state(), const ScanAnyPageState());
  });

  test('late AR result cannot overwrite reset state', () async {
    final file = File('/tmp/narration.mp3');
    ttsClient.results.add(Future.value(file));
    await controller().confirmText('Read me');
    final ar = Completer<void>();
    characterReader.results.add(ar.future);
    final arOperation = controller().openCharacterReader();

    await controller().reset();
    ar.completeError(const CharacterReaderFailure('stale'));
    await arOperation;

    expect(state(), const ScanAnyPageState());
  });

  test('late async results after disposal complete without state writes',
      () async {
    final scan = Completer<String>();
    scanService.results.add(scan.future);
    final operation = controller().startScan();

    container.dispose();
    scan.complete('stale OCR');

    await expectLater(operation, completes);
    expect(ttsClient.disposeCount, 1);
  });
}

final class _FakeScanService implements ScanService {
  final results = <Future<String>>[];
  var callCount = 0;

  @override
  Future<String> scanAndRecognize() {
    callCount++;
    return results.removeAt(0);
  }
}

final class _FakeTtsClient implements TtsClient {
  final results = <Future<File>>[];
  final generatedTexts = <String>[];
  var disposeCount = 0;

  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    generatedTexts.add(confirmedText);
    return results.removeAt(0);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

final class _FakeCharacterReader implements CharacterReader {
  final results = <Future<void>>[];
  final openedPaths = <String>[];

  @override
  Future<void> open(String audioFilePath) {
    openedPaths.add(audioFilePath);
    return results.removeAt(0);
  }
}
