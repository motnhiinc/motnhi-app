import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/http_profile_repository.dart';
import 'package:storybook_ar/data/repositories/http_privacy_repository.dart';
import 'package:storybook_ar/data/repositories/http_session_repository.dart';
import 'package:storybook_ar/data/repositories/authored_story_repository.dart';
import 'package:storybook_ar/data/repositories/http_authored_story_repository.dart';
import 'package:storybook_ar/data/repositories/http_story_repository.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/sources/api_client.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/story_composer/story_draft.dart';

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

  test('concurrent first requests share one device authentication', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final authStarted = Completer<void>();
    final releaseAuth = Completer<void>();
    var authCallCount = 0;

    final authDio = Dio(BaseOptions(baseUrl: 'http://test'));
    authDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (options) async {
        authCallCount++;
        if (!authStarted.isCompleted) authStarted.complete();
        await releaseAuth.future;
        return ResponseBody.fromString(
          jsonEncode({'token': 'shared-token', 'user_id': 'u1'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (options) => ResponseBody.fromString('{}', 200),
    );
    final api = ApiClient(dio: apiDio, store: store, authDio: authDio);

    final requests = [
      api.dio.get('/v1/stories'),
      api.dio.get('/v1/child-profiles'),
    ];
    await authStarted.future;
    await pumpEventQueue();

    expect(authCallCount, 1);

    releaseAuth.complete();
    await Future.wait(requests);
    expect(authCallCount, 1);
  });

  test('retries device authentication after bootstrap failure', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    var authCallCount = 0;

    final authDio = Dio(BaseOptions(baseUrl: 'http://test'));
    authDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (options) {
        authCallCount++;
        if (authCallCount == 1) {
          return ResponseBody.fromString(
            jsonEncode({'detail': 'temporary failure'}),
            500,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(
          jsonEncode({'token': 'retry-token', 'user_id': 'u1'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final apiDio = Dio(BaseOptions(baseUrl: 'http://test'));
    apiDio.httpClientAdapter = _CallCountAdapter(
      onFetch: (options) => ResponseBody.fromString('{}', 200),
    );
    final api = ApiClient(dio: apiDio, store: store, authDio: authDio);

    try {
      await api.dio.get('/v1/stories');
      fail('Expected device authentication to fail');
    } on DioException {
      // Expected: a later request must start a new bootstrap.
    }
    final response = await api.dio.get('/v1/stories');

    expect(response.statusCode, 200);
    expect(store.getString('auth_token'), 'retry-token');
    expect(authCallCount, 2);
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
      a.onGet(
          '/v1/stories',
          (s) => s.reply(200, {
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
    final repo = HttpProfileRepository(api);
    await repo.saveProfile(const ChildProfile(
        id: 'p1', nickname: 'Bun', ageBand: AgeBand.threeToFour));
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
      a.onPost(
          '/v1/story-sessions',
          (s) => s.reply(200, {
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

  // ---------------------------------------------------------------------------
  // HttpAuthoredStoryRepository (capture-to-story)
  // ---------------------------------------------------------------------------

  Future<ApiClient> authedApi(void Function(DioAdapter) wire) async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'd1',
      'auth_token': 'tok',
      'device_secret': 'sec',
    });
    final store = await KeyValueStore.create();
    final (dio, _) = _mockDio(wire);
    return ApiClient(dio: dio, store: store, authDio: dio);
  }

  test('createStory posts contiguous page numbers taken from list order',
      () async {
    Map<String, dynamic>? captured;
    final api = await authedApi((a) {
      a.onPost(
        '/v1/stories',
        (s) => s.reply(201, {
          'id': 'new-id',
          'title': 'My Book',
          'slug': 'authored-x',
          'age_min': 3,
          'age_max': 8,
          'language_code': 'en',
          'duration_seconds': 60,
          'content_status': 'published',
          'themes': <String>[],
          'is_authored': true,
        }),
        data: Matchers.any,
      );
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      captured = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    final story = await HttpAuthoredStoryRepository(api).createStory(
      const StoryDraft(
        title: '  My Book  ',
        pages: [
          DraftPage(localId: 'a', text: 'page one'),
          DraftPage(localId: 'b', text: 'page two'),
        ],
      ),
    );

    expect(captured!['title'], 'My Book');
    expect(
      (captured!['pages'] as List).map((p) => p['page_number']).toList(),
      [1, 2],
    );
    expect(story.id, 'new-id');
    expect(story.isAuthored, isTrue);
  });

  test('createStory maps a 409 to quota_reached', () async {
    final api = await authedApi((a) {
      a.onPost('/v1/stories', (s) => s.reply(409, {'detail': 'limit'}),
          data: Matchers.any);
    });

    await expectLater(
      HttpAuthoredStoryRepository(api).createStory(
        const StoryDraft(
          title: 'T',
          pages: [DraftPage(localId: 'a', text: 'x')],
        ),
      ),
      throwsA(isA<AuthoredStoryFailure>()
          .having((e) => e.code, 'code', 'quota_reached')),
    );
  });

  test('createStory maps a 422 to invalid_story', () async {
    final api = await authedApi((a) {
      a.onPost('/v1/stories', (s) => s.reply(422, {'detail': 'bad'}),
          data: Matchers.any);
    });

    await expectLater(
      HttpAuthoredStoryRepository(api).createStory(
        const StoryDraft(
          title: 'T',
          pages: [DraftPage(localId: 'a', text: 'x')],
        ),
      ),
      throwsA(isA<AuthoredStoryFailure>()
          .having((e) => e.code, 'code', 'invalid_story')),
    );
  });

  test('deleteStory treats a 404 as success', () async {
    final api = await authedApi((a) {
      a.onDelete('/v1/stories/gone', (s) => s.reply(404, {'detail': 'nope'}));
    });

    await expectLater(
      HttpAuthoredStoryRepository(api).deleteStory('gone'),
      completes,
    );
  });

  test('deleteStory surfaces a real failure', () async {
    final api = await authedApi((a) {
      a.onDelete('/v1/stories/s1', (s) => s.reply(500, {'detail': 'boom'}));
    });

    await expectLater(
      HttpAuthoredStoryRepository(api).deleteStory('s1'),
      throwsA(isA<AuthoredStoryFailure>()),
    );
  });

  // ---------------------------------------------------------------------------
  // HttpPrivacyRepository (Task 7 — privacy & consent)
  // ---------------------------------------------------------------------------

  test('fetchPrivacy GETs /v1/privacy and decodes the snake_case payload',
      () async {
    final api = await authedApi((a) {
      a.onGet(
          '/v1/privacy',
          (s) => s.reply(200, {
                'current_policy_version': '2026-09-01',
                'accepted_policy_version': null,
                'review_required': true,
                'core_storage_accepted_at': null,
                'progress_tracking_enabled': false,
                'cloud_tts_enabled': true,
                'effective_progress_tracking_enabled': false,
                'effective_cloud_tts_enabled': true,
                'last_active_at': '2026-09-01T10:00:00Z',
                'updated_at': '2026-09-01T10:00:00Z',
                'counts': {
                  'child_profiles': 2,
                  'authored_stories': 5,
                  'story_sessions': 11,
                  'interaction_events': 42,
                },
              }));
    });

    final state = await HttpPrivacyRepository(api).fetchPrivacy();

    expect(state.currentPolicyVersion, '2026-09-01');
    expect(state.acceptedPolicyVersion, isNull);
    expect(state.reviewRequired, isTrue);
    expect(state.progressTrackingEnabled, isFalse);
    expect(state.cloudTtsEnabled, isTrue);
    expect(state.effectiveProgressTrackingEnabled, isFalse);
    expect(state.effectiveCloudTtsEnabled, isTrue);
    expect(state.lastActiveAt, DateTime.parse('2026-09-01T10:00:00Z'));
    expect(state.updatedAt, DateTime.parse('2026-09-01T10:00:00Z'));
    expect(state.counts.childProfiles, 2);
    expect(state.counts.authoredStories, 5);
    expect(state.counts.storySessions, 11);
    expect(state.counts.interactionEvents, 42);
  });

  test('updatePrivacy PUTs /v1/privacy with a snake_case body', () async {
    Map<String, dynamic>? captured;
    final api = await authedApi((a) {
      a.onPut(
        '/v1/privacy',
        (s) => s.reply(200, {
          'current_policy_version': '2026-09-01',
          'accepted_policy_version': '2026-09-01',
          'review_required': false,
          'core_storage_accepted_at': '2026-09-01T10:00:00Z',
          'progress_tracking_enabled': false,
          'cloud_tts_enabled': true,
          'effective_progress_tracking_enabled': false,
          'effective_cloud_tts_enabled': true,
          'last_active_at': '2026-09-01T10:00:00Z',
          'updated_at': '2026-09-01T10:00:00Z',
          'counts': {
            'child_profiles': 0,
            'authored_stories': 0,
            'story_sessions': 0,
            'interaction_events': 0,
          },
        }),
        data: Matchers.any,
      );
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      captured = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    final state = await HttpPrivacyRepository(api).updatePrivacy(
      policyVersion: '2026-09-01',
      coreStorageAccepted: true,
      progressTrackingEnabled: false,
      cloudTtsEnabled: true,
    );

    expect(captured, {
      'policy_version': '2026-09-01',
      'core_storage_accepted': true,
      'progress_tracking_enabled': false,
      'cloud_tts_enabled': true,
    });
    expect(state.acceptedPolicyVersion, '2026-09-01');
    expect(state.reviewRequired, isFalse);
    expect(state.coreStorageAcceptedAt, DateTime.parse('2026-09-01T10:00:00Z'));
  });

  test('recordActivity POSTs /v1/privacy/activity', () async {
    final api = await authedApi((a) {
      a.onPost('/v1/privacy/activity', (s) => s.reply(204, null));
    });

    await expectLater(HttpPrivacyRepository(api).recordActivity(), completes);
  });

  test('deleteReadingHistory DELETEs /v1/privacy/reading-history', () async {
    final api = await authedApi((a) {
      a.onDelete('/v1/privacy/reading-history', (s) => s.reply(204, null));
    });

    await expectLater(
        HttpPrivacyRepository(api).deleteReadingHistory(), completes);
  });

  test('deleteChildData DELETEs /v1/privacy/child-data', () async {
    final api = await authedApi((a) {
      a.onDelete('/v1/privacy/child-data', (s) => s.reply(204, null));
    });

    await expectLater(HttpPrivacyRepository(api).deleteChildData(), completes);
  });

  test('structured errors decode FastAPI detail into the PrivacyFailure code',
      () async {
    final api = await authedApi((a) {
      a.onGet(
          '/v1/privacy',
          (s) =>
              s.reply(422, {'detail': 'policy_version_required'}));
    });

    await expectLater(
      HttpPrivacyRepository(api).fetchPrivacy(),
      throwsA(isA<PrivacyFailure>()
          .having((e) => e.code, 'code', 'policy_version_required')),
    );
  });

  test('connection failures map to network', () async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'd1',
      'auth_token': 'tok',
      'device_secret': 'sec',
    });
    final store = await KeyValueStore.create();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _CallCountAdapter(
      onFetch: (options) async {
        throw const SocketException('down');
      },
    );
    final api = ApiClient(dio: dio, store: store, authDio: dio);

    await expectLater(
      HttpPrivacyRepository(api).fetchPrivacy(),
      throwsA(isA<PrivacyFailure>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('non-map payloads map to invalid_response', () async {
    final api = await authedApi((a) {
      a.onGet('/v1/privacy', (s) => s.reply(200, 'not-a-map'));
    });

    await expectLater(
      HttpPrivacyRepository(api).fetchPrivacy(),
      throwsA(
          isA<PrivacyFailure>().having((e) => e.code, 'code', 'invalid_response')),
    );
  });

  test('deleteChildData surfaces PrivacyFailure with the server detail',
      () async {
    final api = await authedApi((a) {
      a.onDelete('/v1/privacy/child-data', (s) => s.reply(500, {'detail': 'boom'}));
    });

    await expectLater(
      HttpPrivacyRepository(api).deleteChildData(),
      throwsA(isA<PrivacyFailure>().having((e) => e.code, 'code', 'boom')),
    );
  });

  test('StoryDraft renumbers pages from list order after a removal', () {
    const draft = StoryDraft(
      title: 'T',
      pages: [
        DraftPage(localId: 'b', text: 'second'),
        DraftPage(localId: 'c', text: 'third'),
      ],
    );
    final pages = draft.toJson()['pages'] as List;
    expect(pages.map((p) => p['page_number']).toList(), [1, 2]);
    expect(pages.first['page_text'], 'second');
  });

}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A [HttpClientAdapter] that delegates each fetch to [onFetch].
class _CallCountAdapter implements HttpClientAdapter {
  _CallCountAdapter({required this.onFetch});

  final FutureOr<ResponseBody> Function(RequestOptions) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      await onFetch(options);

  @override
  void close({bool force = false}) {}
}
