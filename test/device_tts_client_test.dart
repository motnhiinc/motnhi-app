import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/scan_any_page/device_tts_client.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('device_tts_client_');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes the clip into the injected directory with the extension',
      () async {
    final synthesizer = _FakeSynthesizer(extension: 'wav');
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    final file = await client.generate('  Read me  ', fileName: 'page_1.mp3');

    expect(file.path, '${temporaryDirectory.path}/page_1.wav');
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), [1]);
    expect(synthesizer.lastText, 'Read me');
    expect(synthesizer.lastPath, file.path);
  });

  test('omitting fileName keeps the existing default name', () async {
    final synthesizer = _FakeSynthesizer(extension: 'wav');
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    final file = await client.generate('Read me');

    expect(file.path, '${temporaryDirectory.path}/scan_any_page_narration.wav');
  });

  test('uses the extension the synthesizer reports', () async {
    final synthesizer = _FakeSynthesizer(extension: 'caf');
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    final file = await client.generate('Read me', fileName: 'page_1.mp3');

    expect(file.path, '${temporaryDirectory.path}/page_1.caf');
    expect(await file.exists(), isTrue);
  });

  for (final invalidText in ['', '   ', 'a' * 4001]) {
    test('rejects invalid text before synthesis', () async {
      final synthesizer = _FakeSynthesizer(extension: 'wav');
      final client = DeviceTtsClient(
        synthesizer,
        directory: () => temporaryDirectory,
      );

      await expectLater(
        client.generate(invalidText),
        throwsA(isA<TtsGenerationFailure>()),
      );
      expect(synthesizer.lastPath, isNull);
    });
  }

  test('rejects a failed synthesis', () async {
    final synthesizer = _FakeSynthesizer(extension: 'wav', success: false);
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('device_synthesis_failed')),
    );
    expect(
      await File('${temporaryDirectory.path}/scan_any_page_narration.wav')
          .exists(),
      isFalse,
    );
  });

  test('rejects a synthesis that reports success but writes no file',
      () async {
    final synthesizer = _FakeSynthesizer(extension: 'wav', writesFile: false);
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('device_synthesis_failed')),
    );
  });

  test('dispose deletes every generated file', () async {
    final synthesizer = _FakeSynthesizer(extension: 'wav');
    final client = DeviceTtsClient(
      synthesizer,
      directory: () => temporaryDirectory,
    );

    final first = await client.generate('one', fileName: 'narr_a.mp3');
    final second = await client.generate('two', fileName: 'narr_b.mp3');
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);

    await client.dispose();

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isFalse);
  });
}

Matcher _failureWithCode(String code) =>
    isA<TtsGenerationFailure>().having((failure) => failure.code, 'code', code);

final class _FakeSynthesizer implements TtsFileSynthesizer {
  _FakeSynthesizer({
    required String extension,
    this.success = true,
    this.writesFile = true,
  }) : fileExtension = extension;

  @override
  final String fileExtension;

  final bool success;
  final bool writesFile;

  String? lastText;
  String? lastPath;

  @override
  Future<bool> synthesizeToFile(String text, String filePath) async {
    lastText = text;
    lastPath = filePath;
    if (success && writesFile) {
      await File(filePath).writeAsBytes([1], flush: true);
    }
    return success;
  }
}
