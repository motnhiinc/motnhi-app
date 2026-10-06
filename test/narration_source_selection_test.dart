import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/player/narration_source_selection.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'narration_source_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  File fileIn(String name) => File('${temporaryDirectory.path}/$name');

  test('prefers the cloud client', () async {
    final cloud = _FakeTtsClient(fileIn('cloud.mp3'));
    final device = _FakeTtsClient(fileIn('device.wav'));

    final selected = selectNarrationSource(
      cloudClient: cloud,
      deviceClient: device,
    );
    final file = await selected.generate('Read me');

    expect(file.path, fileIn('cloud.mp3').path);
    expect(cloud.generateCalls, 1);
    expect(device.generateCalls, 0);
  });

  for (final code in [
    'backend_unreachable',
    'timeout',
    'upstream_failed',
    'rate_limited',
    'authentication',
    'invalid_audio',
  ]) {
    test('a cloud $code failure falls back to the device client', () async {
      final cloud = _FakeTtsClient(
        fileIn('cloud.mp3'),
        failure: _failure(code),
      );
      final device = _FakeTtsClient(fileIn('device.wav'));

      final selected = selectNarrationSource(
        cloudClient: cloud,
        deviceClient: device,
      );
      final file = await selected.generate('Read me');

      expect(file.path, fileIn('device.wav').path);
      expect(cloud.generateCalls, 1);
      expect(device.generateCalls, 1);
    });
  }

  test('invalid text is not caught and never reaches the device', () async {
    final cloud = _FakeTtsClient(
      fileIn('cloud.mp3'),
      failure: _failure('invalid_text'),
    );
    final device = _FakeTtsClient(fileIn('device.wav'));

    final selected = selectNarrationSource(
      cloudClient: cloud,
      deviceClient: device,
    );

    await expectLater(
      selected.generate('Read me'),
      throwsA(_failureWithCode('invalid_text')),
    );
    expect(device.generateCalls, 0);
  });

  test('passes the requested file name to the cloud client', () async {
    final cloud = _FakeTtsClient(fileIn('cloud.mp3'));
    final device = _FakeTtsClient(fileIn('device.wav'));

    final selected = selectNarrationSource(
      cloudClient: cloud,
      deviceClient: device,
    );

    await selected.generate('Read me', fileName: 'page_1.mp3');

    expect(cloud.lastFileName, 'page_1.mp3');
    expect(cloud.lastText, 'Read me');
  });

  test('passes the requested file name to the device fallback', () async {
    final cloud = _FakeTtsClient(
      fileIn('cloud.mp3'),
      failure: _failure('backend_unreachable'),
    );
    final device = _FakeTtsClient(fileIn('device.wav'));

    final selected = selectNarrationSource(
      cloudClient: cloud,
      deviceClient: device,
    );

    await selected.generate('Read me', fileName: 'page_1.mp3');

    expect(device.lastFileName, 'page_1.mp3');
    expect(device.lastText, 'Read me');
  });

  test('dispose disposes both owned clients', () async {
    final cloud = _FakeTtsClient(fileIn('cloud.mp3'));
    final device = _FakeTtsClient(fileIn('device.wav'));

    final selected = selectNarrationSource(
      cloudClient: cloud,
      deviceClient: device,
    );
    await selected.dispose();

    expect(cloud.disposeCalls, 1);
    expect(device.disposeCalls, 1);
  });
}

TtsGenerationFailure _failure(String code) => TtsGenerationFailure(code);

Matcher _failureWithCode(String code) =>
    isA<TtsGenerationFailure>().having((failure) => failure.code, 'code', code);

final class _FakeTtsClient implements TtsClient {
  _FakeTtsClient(this.file, {this.failure});

  final File file;
  final TtsGenerationFailure? failure;

  var generateCalls = 0;
  var disposeCalls = 0;
  String? lastText;
  String? lastFileName;

  @override
  Future<File> generate(String confirmedText, {String? fileName}) {
    generateCalls++;
    lastText = confirmedText;
    lastFileName = fileName;
    final failure = this.failure;
    if (failure != null) return Future.error(failure);
    return Future.value(file);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
