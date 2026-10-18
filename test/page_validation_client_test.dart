import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/data/sources/persistence_keys.dart';
import 'package:storybook_ar/features/scan_any_page/page_validation_client.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mapping in <List<int>?>[
    null,
    [0],
    [1, 0],
    [0, 0, 1],
  ]) {
    test(
      'rejects approval with missing or invalid correction $mapping',
      () async {
        SharedPreferences.setMockInitialValues({authTokenKey: 'token'});
        final store = await KeyValueStore.create();
        final dio = Dio(BaseOptions(baseUrl: 'http://test'));
        final adapter = DioAdapter(
          dio: dio,
          matcher: const UrlRequestMatcher(),
        );
        dio.httpClientAdapter = adapter;
        adapter.onPost(
          '/v1/speakable-page/validate',
          (s) => s.reply(200, {
            'status': 'approved',
            'proof': 'proof',
            if (mapping != null)
              'corrected_lines': [
                {
                  'text': 'Vẹt',
                  'left': .1,
                  'top': .2,
                  'width': .8,
                  'height': .3,
                  'source_lines': mapping,
                  'recognizedLanguage': 'vi',
                },
              ],
          }),
        );
        final client = PageValidationClient(
          ApiClient(dio: dio, store: store, authDio: dio),
        );
        await expectLater(
          client.validate(_page(), 'profile'),
          throwsFormatException,
        );
        await client.dispose();
      },
    );
  }

  test('does not send requests without a profile ID', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    dio.httpClientAdapter = adapter;
    var called = false;
    adapter.onPost('/v1/speakable-page/validate', (s) {
      called = true;
      s.reply(200, {'status': 'blocked'});
    });
    called = false;
    final client = PageValidationClient(
      ApiClient(dio: dio, store: store, authDio: dio),
    );

    await expectLater(client.validate(_page(), ' '), throwsStateError);
    expect(called, isFalse);
    expect(store.getString(authTokenKey), isNull);
    await client.dispose();
  });

  test('sends the exact JPEG and ordered OCR geometry', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    dio.httpClientAdapter = adapter;
    Map<String, dynamic>? captured;
    adapter.onPost(
      '/v1/auth/device',
      (s) => s.reply(200, {'token': 'token', 'user_id': 'user-1'}),
    );
    adapter.onPost(
      '/v1/speakable-page/validate',
      (s) => s.reply(200, {
        'status': 'approved',
        'proof': 'proof-1',
        'corrected_lines': [
          {
            'text': 'First line',
            'left': .1,
            'top': .2,
            'width': .8,
            'height': .1,
            'source_lines': [0],
            'recognizedLanguage': 'en',
          },
          {
            'text': 'Dòng hai.',
            'left': .1,
            'top': .4,
            'width': .8,
            'height': .1,
            'source_lines': [1],
            'recognizedLanguage': 'vi',
          },
        ],
      }),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/v1/speakable-page/validate')) {
            captured = Map<String, dynamic>.from(options.data as Map);
          }
          handler.next(options);
        },
      ),
    );
    final client = PageValidationClient(
      ApiClient(dio: dio, store: store, authDio: dio),
    );
    final page = _page();

    final result = await client.validate(page, 'profile-1');

    expect(result.proof, 'proof-1');
    expect(result.correctedPage!.lines.last.text, 'Dòng hai.');
    expect(result.correctedPage!.lines.first.recognizedLanguage, 'en');
    expect(captured, {
      'profile_id': 'profile-1',
      'correct_ocr': true,
      'image_base64': 'AAECAw==',
      'lines': [
        {
          'text': 'First line',
          'left': .1,
          'top': .2,
          'width': .8,
          'height': .1,
        },
        {'text': 'Dòng hai', 'left': .1, 'top': .4, 'width': .8, 'height': .1},
      ],
    });
    await client.dispose();
  });

  test(
    'rejects incomplete audio archives and removes owned clips on dispose',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await KeyValueStore.create();
      final temp = await Directory.systemTemp.createTemp('page-client-test-');
      final archive = Archive()
        ..addFile(ArchiveFile('000.mp3', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('001.mp3', 3, [4, 5, 6]));
      final zip = ZipEncoder().encode(archive);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      dio.httpClientAdapter = adapter;
      adapter.onPost(
        '/v1/auth/device',
        (s) => s.reply(200, {'token': 'token', 'user_id': 'user-1'}),
      );
      adapter.onPost(
        '/v1/speakable-page/audio',
        (s) => s.reply(
          200,
          zip,
          headers: {
            Headers.contentTypeHeader: ['application/zip'],
          },
        ),
      );
      final client = PageValidationClient(
        ApiClient(dio: dio, store: store, authDio: dio),
        temporaryDirectory: () async => temp,
      );
      final clips = await client.prepareAudio('proof', 'profile-1', [
        'one',
        'two',
      ]);
      expect(clips, hasLength(2));
      expect(await clips[0].readAsBytes(), [1, 2, 3]);

      await client.dispose();

      expect(clips.every((clip) => !clip.existsSync()), isTrue);
      await temp.delete(recursive: true);
    },
  );

  test(
    'rejects archives with missing ordinals before writing any clips',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await KeyValueStore.create();
      final temp = await Directory.systemTemp.createTemp('page-client-test-');
      final archive = Archive()..addFile(ArchiveFile('001.mp3', 3, [1, 2, 3]));
      final zip = ZipEncoder().encode(archive);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      dio.httpClientAdapter = adapter;
      adapter.onPost(
        '/v1/auth/device',
        (s) => s.reply(200, {'token': 'token', 'user_id': 'user-1'}),
      );
      adapter.onPost(
        '/v1/speakable-page/audio',
        (s) => s.reply(
          200,
          zip,
          headers: {
            Headers.contentTypeHeader: ['application/zip'],
          },
        ),
      );
      final client = PageValidationClient(
        ApiClient(dio: dio, store: store, authDio: dio),
        temporaryDirectory: () async => temp,
      );

      await expectLater(
        client.prepareAudio('proof', 'profile-1', ['one']),
        throwsFormatException,
      );
      expect(temp.existsSync(), isTrue);
      expect(temp.listSync(), isEmpty);
      await client.dispose();
      await temp.delete(recursive: true);
    },
  );
}

ScannedPage _page() =>
    ScannedPage(Uint8List.fromList([0, 1, 2, 3]), 440, 585, const [
      ScannedLine('First line', .1, .2, .8, .1),
      ScannedLine('Dòng hai', .1, .4, .8, .1),
    ]);
