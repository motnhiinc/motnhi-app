import '../models/models.dart';
import '../sources/api_client.dart';
import 'session_repository.dart';

/// HTTP implementation of [SessionRepository] backed by /v1/story-sessions
/// (spec §11.3/§11.4 + derived PATCH/GET endpoints).
class HttpSessionRepository implements SessionRepository {
  HttpSessionRepository(this._api);

  final ApiClient _api;

  @override
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) async {
    final resp = await _api.send(() => _api.dio.post('/v1/story-sessions', data: {
      'child_profile_id': childProfileId,
      'story_id': storyId,
      'mode': mode.name,
    }));
    return StorySession.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload = const {},
  }) async {
    await _api.send(() => _api.dio.post('/v1/story-sessions/$sessionId/events', data: {
      'event_type': eventType,
      'page_id': pageId,
      'payload': payload,
    }));
  }

  @override
  Future<void> updateLastPage(String sessionId, int pageNumber) async {
    await _api.send(() => _api.dio.patch('/v1/story-sessions/$sessionId',
        data: {'last_page_number': pageNumber}));
  }

  @override
  Future<void> completeSession(String sessionId) async {
    await _api.send(() => _api.dio
        .patch('/v1/story-sessions/$sessionId', data: {'completed': true}));
  }

  @override
  Future<List<StorySession>> getSessions({String? childProfileId}) async {
    final resp = await _api.send(() => _api.dio.get('/v1/story-sessions',
        queryParameters: {
          'child_profile_id': ?childProfileId,
        }));
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(StorySession.fromJson)
        .toList();
  }

  @override
  Future<List<InteractionEvent>> getEvents({String? sessionId}) async {
    if (sessionId == null) return [];
    final resp =
        await _api.send(() => _api.dio.get('/v1/story-sessions/$sessionId/events'));
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(InteractionEvent.fromJson)
        .toList();
  }
}
