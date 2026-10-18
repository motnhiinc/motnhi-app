import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/data/sources/persistence_keys.dart';
import 'package:storybook_ar/features/scan_any_page/line_audio_player.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/page_validation_client.dart';
import 'package:storybook_ar/features/scan_any_page/scan_page_coordinator.dart';

class _Player implements ScanPagePlayer {
  @override
  final currentLine = ValueNotifier(0);
  @override
  final completed = ValueNotifier(false);
  @override
  final playing = ValueNotifier(false);
  List<File> clips = [];
  @override
  Future<void> load(List<File> files) async {
    clips = files;
  }

  @override
  Future<void> play() async {
    playing.value = true;
  }

  @override
  Future<void> pause() async {
    playing.value = false;
  }

  @override
  Future<void> resume() => play();
  @override
  Future<void> replay() => play();
  @override
  Future<void> stop() => pause();
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native payload → Vietnamese approval → complete ordered ZIP; service retries never retake',
    () async {
      SharedPreferences.setMockInitialValues({authTokenKey: 'token'});
      final store = await KeyValueStore.create();
      final directory = await Directory.systemTemp.createTemp(
        'scan-integration-',
      );
      const channel = MethodChannel('test/scan-integration');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var captures = 0, validations = 0, audioCalls = 0;
      String? nativeAttempt;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captures++;
        nativeAttempt = (call.arguments as Map)['attempt_id'] as String;
        expect((call.arguments as Map)['capture_only'], isTrue);
        return {
          'imageBytes': Uint8List.fromList([1, 2, 3]),
          'width': 100,
          'height': 100,
          'lines': [],
        };
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      dio.httpClientAdapter = adapter;
      final operations = <String>{};
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map;
            expect(data['content_language'], 'vi');
            expect(options.headers['X-Scan-Attempt-Id'], nativeAttempt);
            operations.add(options.headers['X-Scan-Operation-Id'] as String);
            if (options.path.endsWith('/audio')) {
              audioCalls++;
              expect(data['proof'], 'language-bound-proof');
              expect(data['lines'], ['Tiếng Việt. Chú Vẹt nhỏ.']);
              if (audioCalls == 1) {
                handler.reject(
                  DioException.badResponse(
                    statusCode: 503,
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 503,
                      data: utf8.encode('{"detail":"provider_timeout"}'),
                    ),
                  ),
                );
                return;
              }
            } else {
              validations++;
              expect(data['ocr_provider'], 'google_vision');
              expect(data.containsKey('lines'), isFalse);
              if (validations == 1) {
                handler.reject(
                  DioException.badResponse(
                    statusCode: 503,
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 503,
                      data: {
                        'status': 'temporary_error',
                        'reason': 'provider_timeout',
                      },
                    ),
                  ),
                );
                return;
              }
            }
            handler.next(options);
          },
        ),
      );
      adapter.onPost('/v1/speakable-page/validate', (server) {
        server.reply(200, {
          'status': 'approved',
          'proof': 'language-bound-proof',
          'recognized_lines': [
            {
              'text': 'Tiếng Việt. Chú Vẹt nhỏ.',
              'left': .1,
              'top': .1,
              'width': .8,
              'height': .3,
              'recognizedLanguage': 'vi',
            },
          ],
        });
      });
      final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('000.mp3', 2, [1, 2])),
      );
      adapter.onPost('/v1/speakable-page/audio', (server) {
        server.reply(
          200,
          zip,
          headers: {
            Headers.contentTypeHeader: ['application/zip'],
          },
        );
      });
      final player = _Player();
      final session = ScanPageCoordinator(
        scanner: NativeScanService(channel: channel),
        client: PageValidationClient(
          ApiClient(dio: dio, store: store, authDio: dio),
          temporaryDirectory: () async => directory,
        ),
        player: player,
      )..bindPlayback();
      try {
        await session.scan('profile', language: 'vi');
        expect(session.recovery, ScanRecovery.validation);
        await session.retry();
        expect(session.recovery, ScanRecovery.audio);
        expect(session.phase, ScanPagePhase.failed);
        await session.retry();
        expect(session.phase, ScanPagePhase.ready);
        expect(captures, 1);
        expect(validations, 2);
        expect(audioCalls, 2);
        expect(operations, hasLength(4));
        expect(await player.clips.first.readAsBytes(), [1, 2]);
        expect(player.clips, hasLength(1));
        expect(session.page!.lines.single.text, 'Tiếng Việt. Chú Vẹt nhỏ.');
        await session.listen();
        expect(session.phase, ScanPagePhase.playing);
      } finally {
        await session.close();
        session.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        expect(player.clips.every((clip) => !clip.existsSync()), true);
        await directory.delete(recursive: true);
      }
    },
  );
}
