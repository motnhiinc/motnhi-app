import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/asset_url_resolver.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';

(Dio, DioAdapter) _mockDio(void Function(DioAdapter) wire) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
  wire(adapter);
  return (dio, adapter);
}

void main() {
  test('resolves registered ids to absolute URLs and omits unregistered', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/assets/sign', (s) => s.reply(200, {
            'aud_a': '/v1/assets/aud_a?exp=9999999999&sig=ab',
          }));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    final urls = await resolver.resolve(['aud_a', 'aud_missing']);
    expect(urls['aud_a'], 'http://test/v1/assets/aud_a?exp=9999999999&sig=ab');
    expect(urls.containsKey('aud_missing'), isFalse);
  });

  test('caches resolved ids (second call does not re-sign)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    var signCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _PathAdapter((opts) {
      if (opts.path.endsWith('/v1/auth/device')) {
        return ResponseBody.fromString(
          jsonEncode({'token': 't', 'user_id': 'u'}), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      signCalls++; // only /v1/assets/sign reaches here
      return ResponseBody.fromString(
        jsonEncode({'aud_a': '/v1/assets/aud_a?exp=9999999999&sig=ab'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    await resolver.resolve(['aud_a']);
    await resolver.resolve(['aud_a']);
    expect(signCalls, 1);
  });

  test('returns empty map when signing transport errors', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device', (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/assets/sign', (s) => s.reply(500, {'detail': 'boom'}));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpAssetUrlResolver(api);

    final urls = await resolver.resolve(['aud_a']);
    expect(urls, isEmpty);
  });
}

/// A [HttpClientAdapter] that delegates each fetch to [onFetch] (used to count
/// requests reliably; mirrors the helper in http_repositories_test.dart).
class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.onFetch);

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
