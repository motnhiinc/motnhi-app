import 'package:flutter/services.dart';

abstract interface class ScanService {
  Future<String> scanAndRecognize();
}

final class ScanCancelled implements Exception {}

final class ScanFailure implements Exception {
  const ScanFailure(this.code);

  final String code;
}

final class NativeScanService implements ScanService {
  NativeScanService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('storybook_ar/scan_any_page');

  final MethodChannel _channel;

  @override
  Future<String> scanAndRecognize() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('scanAndRecognize');
      final text = result?['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const ScanFailure('no_text');
      }
      return text;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw ScanCancelled();
      throw ScanFailure(error.code);
    }
  }
}
