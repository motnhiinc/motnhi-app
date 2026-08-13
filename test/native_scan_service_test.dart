import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('storybook_ar/scan_any_page');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('returns recognized text', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scanAndRecognize');
      return {'text': 'Hello. Một đêm đẹp.'};
    });

    expect(
      await NativeScanService().scanAndRecognize(),
      'Hello. Một đêm đẹp.',
    );
  });

  test('maps cancelled platform error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'cancelled');
    });

    expect(
      NativeScanService().scanAndRecognize,
      throwsA(isA<ScanCancelled>()),
    );
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

  test('maps empty recognized text to no_text failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'text': '  '});

    expect(
      NativeScanService().scanAndRecognize,
      throwsA(
        isA<ScanFailure>().having((error) => error.code, 'code', 'no_text'),
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
