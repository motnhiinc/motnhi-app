import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart' hide Matcher;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/scan_any_page/tts_client.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    temporaryDirectory = await Directory.systemTemp.createTemp('tts_client_');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('trims text, requests MPEG bytes once, and writes the response',
      () async {
    final requestMatcher = _CapturingRequestMatcher();
    final audio = Uint8List.fromList([1, 2, 3]);
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) {
          server.reply(
            200,
            audio,
            headers: {
              Headers.contentTypeHeader: ['audio/mpeg'],
            },
          );
        },
        data: {'text': 'Read me'},
      ),
      requestMatcher: requestMatcher,
    );

    final file = await client.generate('  Read me  ');

    expect(requestMatcher.matchCount, 1);
    expect(requestMatcher.lastRequest?.data, {'text': 'Read me'});
    expect(requestMatcher.lastRequest?.headers['Accept'], 'audio/mpeg');
    expect(requestMatcher.lastRequest?.responseType, ResponseType.bytes);
    expect(file.path, '${temporaryDirectory.path}/scan_any_page_narration.mp3');
    expect(await file.readAsBytes(), audio);
  });

  test('a second generation replaces the previous file', () async {
    late DioAdapter adapter;
    final client = await _client(
      temporaryDirectory,
      (mockAdapter) {
        adapter = mockAdapter;
        adapter.onPost('/v1/tts', (server) {
          server.reply(
            200,
            Uint8List.fromList([1, 2, 3]),
            headers: {
              Headers.contentTypeHeader: ['audio/mpeg'],
            },
          );
        });
      },
    );

    final first = await client.generate('First');
    adapter.onPost('/v1/tts', (server) {
      server.reply(
        200,
        Uint8List.fromList([4, 5]),
        headers: {
          Headers.contentTypeHeader: ['audio/mpeg'],
        },
      );
    });

    final second = await client.generate('Second');

    expect(second.path, first.path);
    expect(await second.readAsBytes(), [4, 5]);
  });

  for (final invalidText in ['', '   ', 'a' * 4001]) {
    test('rejects invalid text before HTTP', () async {
      final requestMatcher = _CapturingRequestMatcher();
      final client = await _client(
        temporaryDirectory,
        (adapter) => adapter.onPost('/v1/tts', (server) {
          server.reply(200, Uint8List.fromList([1]));
        }),
        requestMatcher: requestMatcher,
      );

      await expectLater(
        client.generate(invalidText),
        throwsA(isA<TtsGenerationFailure>()),
      );
      expect(requestMatcher.matchCount, 0);
    });
  }

  test('rejects a non-200 response as invalid audio', () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          201,
          Uint8List.fromList([1]),
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg'],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('invalid_audio')),
    );
  });

  test('rejects a non-audio response as invalid audio', () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          200,
          Uint8List.fromList([1]),
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('invalid_audio')),
    );
  });

  test('rejects an empty response as invalid audio', () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          200,
          Uint8List(0),
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg'],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('invalid_audio')),
    );
  });

  test('dispose deletes the generated file', () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          200,
          Uint8List.fromList([1]),
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg'],
          },
        ),
      ),
    );
    final file = await client.generate('Read me');

    await client.dispose();

    expect(await file.exists(), isFalse);
  });
}

Future<HttpTtsClient> _client(
  Directory temporaryDirectory,
  void Function(DioAdapter) wire, {
  HttpRequestMatcher requestMatcher = const UrlRequestMatcher(),
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio, matcher: requestMatcher);
  wire(adapter);
  final store = await KeyValueStore.create();
  final apiClient = ApiClient(dio: dio, store: store, authDio: dio);
  return HttpTtsClient(
    apiClient,
    temporaryDirectory: () => temporaryDirectory,
  );
}

Matcher _failureWithCode(String code) =>
    isA<TtsGenerationFailure>().having((failure) => failure.code, 'code', code);

final class _CapturingRequestMatcher extends HttpRequestMatcher {
  RequestOptions? lastRequest;
  var matchCount = 0;

  @override
  bool matches(RequestOptions ongoingRequest, Request matcher) {
    matchCount++;
    lastRequest = ongoingRequest;
    return const UrlRequestMatcher().matches(ongoingRequest, matcher);
  }
}
