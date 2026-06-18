import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/http_profile_repository.dart';
import 'package:storybook_ar/data/repositories/http_session_repository.dart';
import 'package:storybook_ar/data/repositories/http_story_repository.dart';
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
  // ---------------------------------------------------------------------------
  // ApiClient (Task 13)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // HttpStoryRepository (Task 14)
  // ---------------------------------------------------------------------------

  test(
      'HttpStoryRepository.getLibrary recovers from 401: re-mints token and returns data',
      () async {
    // Pre-seed: device already registered with expired token + stored secret.
    SharedPreferences.setMockInitialValues({
      'device_id': 'existing-device',
      'auth_token': 'expired-token',
      'device_secret': 'my-secret',
    });
    final store = await KeyValueStore.create();

    // authDio: re-mint succeeds with new token.
    final (authDio, _) = _mockDio((a) {
      a.onPost(
        '/v1/auth/device',
        (s) => s.reply(200, {'token': 'new-token', 'user_id': 'u1'}),
      );
    });

    // apiDio: first call 401, second call 200 with stories payload.
    var apiCallCount = 0;
    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (opts) {
        apiCallCount++;
        if (apiCallCount == 1) {
          return ResponseBody.fromString(
            jsonEncode({'detail': 'token expired'}),
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(
          jsonEncode({
            'stories': [
              {
                'id': 'story_bunny_forest',
                'title': 'Bunny and the Moon',
                'slug': 'bunny_and_the_moon',
                'age_min': 3,
                'age_max': 5,
                'language_code': 'en',
                'duration_seconds': 300,
                'content_status': 'published',
                'themes': ['animals', 'bedtime'],
                'is_downloaded': false,
                'is_unlocked': true
              }
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final api = ApiClient(dio: apiDio, store: store, authDio: authDio);
    final repo = HttpStoryRepository(api);

    final library = await repo.getLibrary();

    expect(library.length, 1);
    expect(library.single.id, 'story_bunny_forest');
    expect(store.getString('auth_token'), 'new-token');
    expect(apiCallCount, 2); // 401 then retry 200
  });

  test('HttpStoryRepository.getStory returns null on 404', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onGet('/v1/stories/nonexistent',
          (s) => s.reply(404, {'detail': 'not found'}));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final repo = HttpStoryRepository(api);

    final result = await repo.getStory('nonexistent');
    expect(result, isNull);
  });

  test('HttpStoryRepository parses library and detail', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onGet('/v1/stories', (s) => s.reply(200, {
            'stories': [
              {
                'id': 'story_bunny_forest',
                'title': 'Bunny and the Moon',
                'slug': 'bunny_and_the_moon',
                'age_min': 3,
                'age_max': 5,
                'language_code': 'en',
                'duration_seconds': 300,
                'content_status': 'published',
                'themes': ['animals', 'bedtime'],
                'is_downloaded': false,
                'is_unlocked': true
              }
            ]
          }));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final repo = HttpStoryRepository(api);
    final lib = await repo.getLibrary();
    expect(lib.single.id, 'story_bunny_forest');
    expect(lib.single.title, 'Bunny and the Moon');
  });

  // ---------------------------------------------------------------------------
  // HttpProfileRepository (Task 15)
  // ---------------------------------------------------------------------------

  test('HttpProfileRepository saves and reads back a profile', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    const pjson = {
      'id': 'p1',
      'user_id': 'u',
      'nickname': 'Bun',
      'age_band': '3-4',
      'language_code': 'en',
      'bedtime_mode_default': false,
      'microphone_enabled': false,
      'ar_enabled': true
    };

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/child-profiles', (s) => s.reply(200, pjson));
      a.onGet('/v1/child-profiles', (s) => s.reply(200, [pjson]));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final repo = HttpProfileRepository(api, store);
    await repo.saveProfile(
        const ChildProfile(id: 'p1', nickname: 'Bun', ageBand: AgeBand.threeToFour));
    final got = await repo.getProfile();
    expect(got!.nickname, 'Bun');
    expect(got.ageBand, AgeBand.threeToFour);
  });

  // ---------------------------------------------------------------------------
  // HttpSessionRepository (Task 16)
  // ---------------------------------------------------------------------------

  test('HttpSessionRepository starts a session and parses it', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();

    final (dio, _) = _mockDio((a) {
      a.onPost('/v1/auth/device',
          (s) => s.reply(200, {'token': 't', 'user_id': 'u'}));
      a.onPost('/v1/story-sessions', (s) => s.reply(200, {
            'id': 'sess1',
            'child_profile_id': 'p1',
            'story_id': 'story_bunny_forest',
            'started_at': '2026-06-18T10:00:00Z',
            'completed_at': null,
            'last_page_number': 0,
            'mode': 'bedtime'
          }));
    });

    final api = ApiClient(dio: dio, store: store, authDio: dio);
    final repo = HttpSessionRepository(api);
    final session = await repo.startSession(
        childProfileId: 'p1',
        storyId: 'story_bunny_forest',
        mode: SessionMode.bedtime);
    expect(session.id, 'sess1');
    expect(session.mode, SessionMode.bedtime);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
