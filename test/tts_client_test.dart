import 'dart:async';
import 'dart:convert';
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

  test('serializes generations so the later call owns the final audio',
      () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var requestCount = 0;
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        return _audioResponse(requestCount == 1 ? [1] : [2]);
      }),
    );

    final first = client.generate('First');
    await firstStarted.future;
    final second = client.generate('Second');
    await pumpEventQueue();

    expect(requestCount, 1);
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(requestCount, 2);
    expect(
      await File('${temporaryDirectory.path}/scan_any_page_narration.mp3')
          .readAsBytes(),
      [2],
    );
  });

  test(
      'dispose waits for in-flight generation and leaves no audio or temp file',
      () async {
    final requestStarted = Completer<void>();
    final releaseRequest = Completer<void>();
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter((options) async {
        requestStarted.complete();
        await releaseRequest.future;
        return _audioResponse([1]);
      }),
    );

    final generation = client.generate('Read me');
    await requestStarted.future;
    final disposal = client.dispose();
    releaseRequest.complete();
    await generation;
    await disposal;

    expect(
      await File('${temporaryDirectory.path}/scan_any_page_narration.mp3')
          .exists(),
      isFalse,
    );
    expect(
      temporaryDirectory.listSync().whereType<File>(),
      isEmpty,
    );
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

  test('validates the 4000-character limit by Unicode code points', () async {
    final requestMatcher = _CapturingRequestMatcher();
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
      requestMatcher: requestMatcher,
    );
    final supplementaryCharacter = String.fromCharCode(0x1F642);

    await client.generate(supplementaryCharacter * 4000);
    await expectLater(
      client.generate(supplementaryCharacter * 4001),
      throwsA(_failureWithCode('invalid_text')),
    );

    expect(requestMatcher.matchCount, 1);
  });

  test('refreshes authentication and retries TTS after a 401', () async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'existing-device',
      'auth_token': 'expired-token',
      'device_secret': 'secret',
    });
    final store = await KeyValueStore.create();
    final authDio = Dio(BaseOptions(baseUrl: 'http://test'));
    final authAdapter = DioAdapter(
      dio: authDio,
      matcher: const UrlRequestMatcher(),
    );
    authAdapter.onPost(
      '/v1/auth/device',
      (server) => server.reply(200, {'token': 'new-token', 'user_id': 'user'}),
    );
    var requestCount = 0;
    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _StubAdapter((options) {
      requestCount++;
      if (requestCount == 1) {
        return ResponseBody.fromString(
          jsonEncode({'detail': 'expired'}),
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      expect(options.headers['Authorization'], 'Bearer new-token');
      return _audioResponse([7]);
    });
    final client = HttpTtsClient(
      ApiClient(dio: apiDio, store: store, authDio: authDio),
      temporaryDirectory: () => temporaryDirectory,
    );

    final file = await client.generate('Read me');

    expect(await file.readAsBytes(), [7]);
    expect(requestCount, 2);
    expect(store.getString('auth_token'), 'new-token');
  });

  test('maps a repeated 401 after authentication refresh', () async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'existing-device',
      'auth_token': 'expired-token',
      'device_secret': 'secret',
    });
    final store = await KeyValueStore.create();
    final authDio = Dio(BaseOptions(baseUrl: 'http://test'));
    final authAdapter = DioAdapter(
      dio: authDio,
      matcher: const UrlRequestMatcher(),
    );
    authAdapter.onPost(
      '/v1/auth/device',
      (server) => server.reply(200, {'token': 'new-token', 'user_id': 'user'}),
    );
    var requestCount = 0;
    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _StubAdapter((options) {
      requestCount++;
      return ResponseBody.fromString('unauthorized', 401);
    });
    final client = HttpTtsClient(
      ApiClient(dio: apiDio, store: store, authDio: authDio),
      temporaryDirectory: () => temporaryDirectory,
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('authentication')),
    );

    expect(requestCount, 2);
    expect(store.getString('auth_token'), 'new-token');
  });

  for (final (type, code) in [
    (DioExceptionType.connectionError, 'backend_unreachable'),
    (DioExceptionType.connectionTimeout, 'timeout'),
    (DioExceptionType.sendTimeout, 'timeout'),
    (DioExceptionType.receiveTimeout, 'timeout'),
  ]) {
    test('maps $type to $code', () async {
      final client = await _clientWithAdapter(
        temporaryDirectory,
        _StubAdapter(
          (options) => throw DioException(
            requestOptions: options,
            type: type,
          ),
        ),
      );

      await expectLater(
        client.generate('Read me'),
        throwsA(_failureWithCode(code)),
      );
    });
  }

  test('maps a socket connection failure to backend_unreachable', () async {
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const SocketException('connection failed'),
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('backend_unreachable')),
    );
  });

  test('maps a 403 cloud_tts_disabled detail before status mapping', () async {
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter(
        (_) => ResponseBody.fromString(
          jsonEncode({'detail': 'cloud_tts_disabled'}),
          403,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('cloud_tts_disabled')),
    );
  });

  test('maps a 401 cloud_tts_disabled detail before status mapping', () async {
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter(
        (_) => ResponseBody.fromBytes(
          utf8.encode(jsonEncode({'detail': 'cloud_tts_disabled'})),
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('cloud_tts_disabled')),
    );
  });

  test('maps an unrelated 403 detail to authentication', () async {
    final client = await _clientWithAdapter(
      temporaryDirectory,
      _StubAdapter(
        (_) => ResponseBody.fromString(
          jsonEncode({'detail': 'expired'}),
          403,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    await expectLater(
      client.generate('Read me'),
      throwsA(_failureWithCode('authentication')),
    );
  });

  for (final (statusCode, code) in [
    (403, 'authentication'),
    (429, 'rate_limited'),
    (500, 'upstream_failed'),
  ]) {
    test('maps HTTP $statusCode to $code', () async {
      final client = await _clientWithAdapter(
        temporaryDirectory,
        _StubAdapter(
          (_) => ResponseBody.fromString('failure', statusCode),
        ),
      );

      await expectLater(
        client.generate('Read me'),
        throwsA(_failureWithCode(code)),
      );
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

  test('accepts case-insensitive MPEG content type with standard parameters',
      () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          200,
          Uint8List.fromList([1]),
          headers: {
            Headers.contentTypeHeader: ['Audio/MPEG; charset=binary'],
          },
        ),
      ),
    );

    expect(await (await client.generate('Read me')).readAsBytes(), [1]);
  });

  test('accepts a quoted content type parameter containing a comma', () async {
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(
          200,
          Uint8List.fromList([1]),
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg; note="one,two"'],
          },
        ),
      ),
    );

    expect(await (await client.generate('Read me')).readAsBytes(), [1]);
  });

  for (final contentTypes in [
    ['audio/mpeg', 'audio/mpeg'],
    ['audio/mpeg, application/json'],
    ['audio/mpeg; charset'],
    ['audio/mpeg; =binary'],
  ]) {
    test('rejects duplicate or malformed content type $contentTypes', () async {
      final client = await _client(
        temporaryDirectory,
        (adapter) => adapter.onPost(
          '/v1/tts',
          (server) => server.reply(
            200,
            Uint8List.fromList([1]),
            headers: {Headers.contentTypeHeader: contentTypes},
          ),
        ),
      );

      await expectLater(
        client.generate('Read me'),
        throwsA(_failureWithCode('invalid_audio')),
      );
    });
  }

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

  test('failed atomic replacement preserves valid audio and cleans temp files',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    adapter.onPost('/v1/tts', (server) {
      server.reply(
        200,
        Uint8List.fromList([1]),
        headers: {
          Headers.contentTypeHeader: ['audio/mpeg'],
        },
      );
    });
    final store = await KeyValueStore.create();
    final client = HttpTtsClient(
      ApiClient(dio: dio, store: store, authDio: dio),
      temporaryDirectory: () => temporaryDirectory,
    );
    final validFile = await client.generate('First');
    final blockedTemporaryPath =
        '${temporaryDirectory.path}/.scan_any_page_narration.mp3.2.tmp';
    await Directory(blockedTemporaryPath).create();

    await expectLater(
        client.generate('Second'), throwsA(isA<FileSystemException>()));

    expect(await validFile.readAsBytes(), [1]);
    expect(
      temporaryDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp')),
      isEmpty,
    );
    await Directory(blockedTemporaryPath).delete();
  });

  test('distinct file names do not clobber each other', () async {
    final audio = Uint8List.fromList([1, 2, 3]);
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(200, audio, headers: {
          Headers.contentTypeHeader: ['audio/mpeg'],
        }),
      ),
    );

    final first = await client.generate('page one', fileName: 'narr_a.mp3');
    final second = await client.generate('page two', fileName: 'narr_b.mp3');

    expect(first.path, isNot(second.path));
    expect(first.path, '${temporaryDirectory.path}/narr_a.mp3');
    expect(second.path, '${temporaryDirectory.path}/narr_b.mp3');
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
  });

  test('dispose deletes every generated file', () async {
    final audio = Uint8List.fromList([1, 2, 3]);
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(200, audio, headers: {
          Headers.contentTypeHeader: ['audio/mpeg'],
        }),
      ),
    );

    final first = await client.generate('one', fileName: 'narr_a.mp3');
    final second = await client.generate('two', fileName: 'narr_b.mp3');
    await client.dispose();

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isFalse);
  });

  test('omitting fileName keeps the existing default name', () async {
    final audio = Uint8List.fromList([1, 2, 3]);
    final client = await _client(
      temporaryDirectory,
      (adapter) => adapter.onPost(
        '/v1/tts',
        (server) => server.reply(200, audio, headers: {
          Headers.contentTypeHeader: ['audio/mpeg'],
        }),
      ),
    );

    final file = await client.generate('text');

    expect(file.path, '${temporaryDirectory.path}/scan_any_page_narration.mp3');
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

Future<HttpTtsClient> _clientWithAdapter(
  Directory temporaryDirectory,
  HttpClientAdapter adapter,
) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  final store = await KeyValueStore.create();
  return HttpTtsClient(
    ApiClient(dio: dio, store: store, authDio: dio),
    temporaryDirectory: () => temporaryDirectory,
  );
}

ResponseBody _audioResponse(List<int> bytes) => ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['audio/mpeg'],
      },
    );

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

final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onFetch);

  final FutureOr<ResponseBody> Function(RequestOptions) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      await onFetch(options);

  @override
  void close({bool force = false}) {}
}
