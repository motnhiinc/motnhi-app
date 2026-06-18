import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';

/// Creates a [Dio] + [DioAdapter] pair configured by [wire].
/// Uses [UrlRequestMatcher] so mock routes match by path only.
(Dio, DioAdapter) _mockDio(void Function(DioAdapter) wire) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
  wire(adapter);
  return (dio, adapter);
}

void main() {
  test('bootstraps a device token and attaches it as Bearer', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't0k', 'user_id': 'u1'}));
      a.onGet('/v1/stories', (s) => s.reply(200, {'stories': []}));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resp = await api.dio.get('/v1/stories');
    expect(resp.statusCode, 200);
    expect(api.userId, 'u1');
  });

  test('persists device_secret on first registration', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost(
        '/v1/auth/device',
        (s) => s.reply(200, {
          'token': 'tok1',
          'user_id': 'u1',
          'device_secret': 'secret123',
        }),
      );
      a.onGet('/v1/stories', (s) => s.reply(200, {'stories': []}));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    await api.dio.get('/v1/stories');

    expect(store.getString('device_secret'), 'secret123');
  });

  test(
      'ApiClient.send() on 401: clears token, re-mints with stored secret, retries',
      () async {
    // Pre-seed: device exists with expired token + stored secret.
    SharedPreferences.setMockInitialValues({
      'device_id': 'existing-device',
      'auth_token': 'expired-token',
      'device_secret': 'my-secret',
    });
    final store = await KeyValueStore.create();

    // authDio: handles re-mint
    final (authDio, _) = _mockDio((a) {
      a.onPost(
        '/v1/auth/device',
        (s) => s.reply(200, {'token': 'new-token', 'user_id': 'u1'}),
      );
    });

    // apiDio: stateful adapter — first call 401, second call 200
    var apiCallCount = 0;
    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (opts) {
        apiCallCount++;
        if (apiCallCount == 1) {
          return ResponseBody.fromString(
            jsonEncode({'detail': 'expired'}),
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(
          jsonEncode({'stories': []}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final api = ApiClient(dio: apiDio, store: store, authDio: authDio);

    // send() handles the 401 → re-mint → retry cycle
    final resp = await api.send(() => api.dio.get('/v1/stories'));
    expect(resp.statusCode, 200);
    expect(store.getString('auth_token'), 'new-token');
    expect(store.getString('device_secret'), 'my-secret');
    expect(apiCallCount, 2); // called twice: first 401, then retry 200
  });
}

/// A [HttpClientAdapter] that delegates each fetch to [onFetch].
class _CallCountAdapter implements HttpClientAdapter {
  _CallCountAdapter({required this.onFetch});

  final ResponseBody Function(RequestOptions) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      onFetch(options);

  @override
  void close({bool force = false}) {}
}
