import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page_ar_audio.dart';

void main() {
  late Directory root;
  late ScannedPageArAudio audio;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scan-ar-test-');
    audio = ScannedPageArAudio(temporaryDirectory: () async => root);
  });

  tearDown(() async {
    await audio.dispose();
    await root.delete(recursive: true);
  });

  Future<File> clip(String name, List<int> bytes) =>
      File('${root.path}/$name').writeAsBytes(bytes);

  test(
    'preserves every line in order using native-compatible copies',
    () async {
      final first = await clip('000.mp3', [1, 2]);
      final second = await clip('001.mp3', [3, 4]);
      final page = await audio.prepare([first, second]);

      expect(page.pageId, 'scanned-page');
      expect(page.pageNumber, 1);
      expect(page.audioFilePaths, hasLength(2));
      final allowedName = RegExp(
        r'^ar_[A-Za-z0-9]{1,32}_p\d{1,4}_s\d{1,4}\.mp3$',
      );
      for (final path in page.audioFilePaths) {
        expect(path, startsWith('${root.path}/scan-ar-'));
        expect(allowedName.hasMatch(File(path).uri.pathSegments.last), isTrue);
      }
      expect(await File(page.audioFilePaths[0]).readAsBytes(), [1, 2]);
      expect(await File(page.audioFilePaths[1]).readAsBytes(), [3, 4]);
      expect(await audio.prepare([first, second]), same(page));

      await audio.dispose();
      expect(await File(page.audioFilePaths.first).exists(), isFalse);
      expect(await first.readAsBytes(), [1, 2]);
      expect(await second.readAsBytes(), [3, 4]);
    },
  );

  test('partial failure removes copies and permits retry', () async {
    final first = await clip('000.mp3', [1]);
    final missing = File('${root.path}/001.mp3');

    await expectLater(
      audio.prepare([first, missing]),
      throwsA(isA<ArNarrationFailure>()),
    );
    expect(await root.list().map((entry) => entry.path).toList(), [first.path]);

    await missing.writeAsBytes([2]);
    final page = await audio.prepare([first, missing]);
    expect(await File(page.audioFilePaths.last).readAsBytes(), [2]);
  });

  test(
    'rejects empty audio and segment indexes outside native limits',
    () async {
      final empty = await clip('empty.mp3', []);
      for (final clips in [
        <File>[],
        [empty],
        List.filled(10001, empty),
      ]) {
        await expectLater(
          audio.prepare(clips),
          throwsA(isA<ArNarrationFailure>()),
        );
      }
      expect(await root.list().map((entry) => entry.path).toList(), [empty.path]);
    },
  );

  test(
    'cleanup waits for pending preparation and prevents late copies',
    () async {
      final directory = Completer<Directory>();
      await audio.dispose();
      audio = ScannedPageArAudio(temporaryDirectory: () => directory.future);
      final source = await clip('000.mp3', [1]);
      final preparation = audio.prepare([source]);
      final cancelled = expectLater(
        preparation,
        throwsA(
          isA<ArNarrationFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      var disposed = false;
      final disposal = audio.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);

      directory.complete(root);
      await cancelled;
      await disposal;
      expect(await root.list().map((entry) => entry.path).toList(), [source.path]);
      await expectLater(
        audio.prepare([source]),
        throwsA(isA<ArNarrationFailure>()),
      );
    },
  );
}
