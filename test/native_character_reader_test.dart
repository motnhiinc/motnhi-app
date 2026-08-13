import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/native_character_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('storybook_ar/character_reader');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('opens character reader and returns when completed', () async {
    const path = '/tmp/narration.mp3';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openCharacterReader');
      expect(call.arguments, {'audioFilePath': path});
      return 'completed';
    });

    await expectLater(NativeCharacterReader().open(path), completes);
  });

  test('maps cancelled platform error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'cancelled');
    });

    expect(
      NativeCharacterReader().open('/tmp/narration.mp3'),
      throwsA(isA<CharacterReaderCancelled>()),
    );
  });

  test('maps other platform errors with their code', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'reader_in_progress');
    });

    expect(
      NativeCharacterReader().open('/tmp/narration.mp3'),
      throwsA(
        isA<CharacterReaderFailure>().having(
          (error) => error.code,
          'code',
          'reader_in_progress',
        ),
      ),
    );
  });
}
