import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('storybook_ar/scan_any_page');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('returns corrected image and ordered OCR geometry', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scanAndRecognize');
      return {
        'imageBytes': Uint8List.fromList([0xff, 0xd8, 0xff]),
        'width': 440,
        'height': 585,
        'lines': [
          {
            'text': 'Hello.',
            'left': 0.1,
            'top': 0.1,
            'width': 0.8,
            'height': 0.1,
          },
          {
            'text': 'Một đêm đẹp.',
            'left': 0.1,
            'top': 0.3,
            'width': 0.8,
            'height': 0.1,
          },
        ],
      };
    });

    expect(
      await NativeScanService().scanAndRecognize(),
      isA<ScannedPage>().having(
        (page) => page.joinedText,
        'joinedText',
        'Hello.\nMột đêm đẹp.',
      ),
    );
  });

  test('maps cancelled platform error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'cancelled');
    });

    expect(NativeScanService().scanAndRecognize, throwsA(isA<ScanCancelled>()));
  });

  test('maps null native result to no_text failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(
      NativeScanService().scanAndRecognize,
      throwsA(
        isA<ScanFailure>().having((error) => error.code, 'code', 'no_text'),
      ),
    );
  });

  test('rejects malformed page result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'text': '  '});

    expect(
      NativeScanService().scanAndRecognize,
      throwsA(
        isA<ScanFailure>().having(
          (error) => error.code,
          'code',
          'invalid_result',
        ),
      ),
    );
  });

  test('maps other platform errors with their code', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'camera_unavailable');
    });

    expect(
      NativeScanService().scanAndRecognize,
      throwsA(
        isA<ScanFailure>().having(
          (error) => error.code,
          'code',
          'camera_unavailable',
        ),
      ),
    );
  });
}
