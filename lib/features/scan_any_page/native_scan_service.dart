import 'package:flutter/services.dart';
import 'scanned_page.dart';

abstract interface class ScanService {
  Future<ScannedPage> scanAndRecognize();
}

final class ScanCancelled implements Exception {}

final class ScanFailure implements Exception {
  const ScanFailure(this.code);

  final String code;
}

final class NativeScanService implements ScanService {
  NativeScanService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('storybook_ar/scan_any_page');

  final MethodChannel _channel;

  @override
  Future<ScannedPage> scanAndRecognize() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'scanAndRecognize',
      );
      if (result == null) throw const ScanFailure('no_text');
      try {
        return ScannedPage.fromMap(result);
      } on Object {
        throw const ScanFailure('invalid_result');
      }
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw ScanCancelled();
      throw ScanFailure(error.code);
    }
  }
}
