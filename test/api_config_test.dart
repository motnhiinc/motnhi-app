import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/api_config.dart';

void main() {
  group('resolveApiBaseUrl', () {
    test('defaults to localhost in debug mode', () {
      expect(
        resolveApiBaseUrl(isRelease: false),
        'http://localhost:8000',
      );
    });

    test('accepts an explicit HTTPS URL in release mode', () {
      expect(
        resolveApiBaseUrl(
          configuredUrl: 'https://api.example.com',
          isRelease: true,
        ),
        'https://api.example.com',
      );
    });

    test('accepts a non-loopback hostname beginning with 127', () {
      expect(
        resolveApiBaseUrl(
          configuredUrl: 'https://127.example.com',
          isRelease: true,
        ),
        'https://127.example.com',
      );
    });

    test('accepts a non-loopback trailing-dot FQDN', () {
      expect(
        resolveApiBaseUrl(
          configuredUrl: 'https://api.example.com.',
          isRelease: true,
        ),
        'https://api.example.com.',
      );
    });

    for (final invalidUrl in [
      '',
      'http://api.example.com',
      'https://localhost',
      'https://localhost.',
      'https://127',
      'https://127.1',
      'https://127.0.1',
      'https://127.0.0.1',
      'https://127.0.0.1.',
      'https://127.0.0.2',
      'https://127.255.255.255',
      'https://[::1]',
      'https://[0:0:0:0:0:0:0:1]',
      'https://[::ffff:127.0.0.1]',
    ]) {
      test('rejects "$invalidUrl" in release mode', () {
        expect(
          () => resolveApiBaseUrl(
            configuredUrl: invalidUrl,
            isRelease: true,
          ),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('API_BASE_URL'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('--dart-define=API_BASE_URL='),
                ),
          ),
        );
      });
    }
  });
}
