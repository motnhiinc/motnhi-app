import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/image_target_resolver.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';

const _storyId = 'story_bunny_forest';
const _manifestPath = '/v1/stories/$_storyId/image-target-manifest';

const _manifestJson = {
  'story_id': _storyId,
  'version': 1,
  'targets': [
    {
      'page_id': 'page_bunny_03',
      'page_number': 3,
      'image_target_id': 'imgt_page_bunny_03',
      'reference_image_url': null,
      'physical_width_mm': 210,
    },
  ],
};

(Dio, DioAdapter) _mockDio(void Function(DioAdapter) wire) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
  wire(adapter);
  return (dio, adapter);
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  test('fetch parses the manifest', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onGet(_manifestPath, (s) => s.reply(200, _manifestJson));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpImageTargetResolver(api);

    final manifest = await resolver.fetch(_storyId);
    expect(manifest.storyId, _storyId);
    expect(manifest.version, 1);
    expect(manifest.targets.single.pageId, 'page_bunny_03');
    expect(manifest.targets.single.imageTargetId, 'imgt_page_bunny_03');
    expect(manifest.targets.single.referenceImageUrl, isNull);
    expect(manifest.targets.single.physicalWidthMm, 210);
  });

  test('caches the manifest (second fetch does not re-request)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    var manifestCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _StubAdapter((opts) {
      if (opts.path.endsWith('/v1/auth/device')) {
        return _json({'token': 't', 'user_id': 'u'});
      }
      manifestCalls++; // only the manifest GET reaches here
      return _json(_manifestJson);
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpImageTargetResolver(api);

    await resolver.fetch(_storyId);
    await resolver.fetch(_storyId);
    expect(manifestCalls, 1);
  });

  test('recovers from 401 by re-minting the token then succeeds', () async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'existing-device',
      'auth_token': 'expired-token',
      'device_secret': 'my-secret',
    });
    final store = await KeyValueStore.create();

    // authDio: re-mint succeeds with a new token.
    final (authDio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 'new-token', 'user_id': 'u1'}));
    });

    // apiDio: first call 401, retry 200 with the manifest.
    var apiCallCount = 0;
    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _StubAdapter((opts) {
      apiCallCount++;
      if (apiCallCount == 1) return _json({'detail': 'expired'}, 401);
      return _json(_manifestJson);
    });

    final api = ApiClient(dio: apiDio, store: store, authDio: authDio);
    final resolver = HttpImageTargetResolver(api);

    final manifest = await resolver.fetch(_storyId);
    expect(manifest.targets.single.pageId, 'page_bunny_03');
    expect(store.getString('auth_token'), 'new-token');
    expect(apiCallCount, 2); // 401 then retry 200
  });

  test('returns the cached manifest when the network later fails', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    var fail = false;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _StubAdapter((opts) {
      if (opts.path.endsWith('/v1/auth/device')) {
        return _json({'token': 't', 'user_id': 'u'});
      }
      if (fail) return _json({'detail': 'boom'}, 500);
      return _json(_manifestJson);
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final resolver = HttpImageTargetResolver(api);

    final first = await resolver.fetch(_storyId); // caches
    fail = true;
    final second = await resolver.fetch(_storyId); // resolved from cache

    expect(second.storyId, first.storyId);
    expect(second.targets.single.pageId, 'page_bunny_03');
  });
}

/// A [HttpClientAdapter] that delegates each fetch to [onFetch]; mirrors the
/// counting helpers in asset_url_resolver_test / http_repositories_test.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onFetch);

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
