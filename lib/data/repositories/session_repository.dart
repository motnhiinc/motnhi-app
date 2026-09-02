import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../sources/key_value_store.dart';

/// Tracks story sessions and interaction events (§9.5.6). Backs
/// `POST /v1/story-sessions` (§11.3) and `.../events` (§11.4). Persisted
/// locally; aggregated for the parent dashboard (§7.2.2) and analytics (§16).
abstract class SessionRepository {
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  });

  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload,
  });

  /// Persist resume state (§9.5.6 `last_page_number`).
  Future<void> updateLastPage(String sessionId, int pageNumber);

  /// Mark the story finished (§16.1 completion metric).
  Future<void> completeSession(String sessionId);

  Future<List<StorySession>> getSessions({String? childProfileId});
  Future<List<InteractionEvent>> getEvents({String? sessionId});
}

/// Typed failure raised by session writes; `code` preserves the upstream
/// detail (e.g. `progress_tracking_disabled`), or `network` /
/// `invalid_response` when no detail is available.
class SessionFailure implements Exception {
  const SessionFailure(this.code);

  final String code;
}

class LocalSessionRepository implements SessionRepository {
  LocalSessionRepository(this._store, {Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final Uuid _uuid;
  final DateTime Function() _clock;

  static const _sessionsKey = 'story_sessions';
  static const _eventsKey = 'interaction_events';

  List<StorySession> _readSessions() =>
      (_store.readJsonList(_sessionsKey) ?? const [])
          .map((e) => StorySession.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> _writeSessions(List<StorySession> sessions) =>
      _store.writeJson(_sessionsKey, sessions.map((s) => s.toJson()).toList());

  List<InteractionEvent> _readEvents() =>
      (_store.readJsonList(_eventsKey) ?? const [])
          .map((e) => InteractionEvent.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> _writeEvents(List<InteractionEvent> events) =>
      _store.writeJson(_eventsKey, events.map((e) => e.toJson()).toList());

  @override
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) async {
    final session = StorySession(
      id: _uuid.v4(),
      childProfileId: childProfileId,
      storyId: storyId,
      startedAt: _clock(),
      mode: mode,
    );
    await _writeSessions([..._readSessions(), session]);
    await recordEvent(
      sessionId: session.id,
      eventType: 'story_started',
      payload: {'story_id': storyId, 'mode': mode.name},
    );
    return session;
  }

  @override
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload = const {},
  }) async {
    final event = InteractionEvent(
      id: _uuid.v4(),
      storySessionId: sessionId,
      eventType: eventType,
      pageId: pageId,
      payload: payload,
      createdAt: _clock(),
    );
    await _writeEvents([..._readEvents(), event]);
  }

  @override
  Future<void> updateLastPage(String sessionId, int pageNumber) async {
    final sessions = _readSessions();
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    sessions[idx] = sessions[idx].copyWith(lastPageNumber: pageNumber);
    await _writeSessions(sessions);
  }

  @override
  Future<void> completeSession(String sessionId) async {
    final sessions = _readSessions();
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    sessions[idx] = sessions[idx].copyWith(completedAt: _clock());
    await _writeSessions(sessions);
    await recordEvent(sessionId: sessionId, eventType: 'story_completed');
  }

  @override
  Future<List<StorySession>> getSessions({String? childProfileId}) async {
    final sessions = _readSessions();
    if (childProfileId == null) return sessions;
    return sessions
        .where((s) => s.childProfileId == childProfileId)
        .toList();
  }

  @override
  Future<List<InteractionEvent>> getEvents({String? sessionId}) async {
    final events = _readEvents();
    if (sessionId == null) return events;
    return events.where((e) => e.storySessionId == sessionId).toList();
  }
}
