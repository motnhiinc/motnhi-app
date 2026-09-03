import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/repositories/session_repository.dart';
import 'package:storybook_ar/data/repositories/story_repository.dart';
import 'package:storybook_ar/features/dashboard/dashboard_providers.dart';
import 'package:storybook_ar/features/profile/profile_providers.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Minimal in-memory [SessionRepository] that returns pre-set sessions and
/// per-session events. [getEvents] with no sessionId returns [] (same as
/// [HttpSessionRepository]), so this test FAILS under the old call-without-arg
/// code path and PASSES after the fan-out fix.
class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({
    List<StorySession> sessions = const [],
    Map<String, List<InteractionEvent>> eventsBySession = const {},
    this.getSessionsError,
  })  : _sessions = sessions,
        _eventsBySession = eventsBySession;

  final List<StorySession> _sessions;
  final Map<String, List<InteractionEvent>> _eventsBySession;

  /// When set, [getSessions] throws instead of returning sessions — simulates
  /// a remote session-list failure (§14: must surface as an error, never as
  /// empty history).
  final Object? getSessionsError;

  @override
  Future<List<StorySession>> getSessions({String? childProfileId}) async {
    final error = getSessionsError;
    if (error != null) throw error;
    return childProfileId == null
        ? _sessions
        : _sessions
            .where((s) => s.childProfileId == childProfileId)
            .toList();
  }

  @override
  Future<List<InteractionEvent>> getEvents({String? sessionId}) async {
    // Mirrors HttpSessionRepository: returns [] when sessionId is null.
    if (sessionId == null) return [];
    return _eventsBySession[sessionId] ?? [];
  }

  @override
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload = const {},
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateLastPage(String sessionId, int pageNumber) =>
      throw UnimplementedError();

  @override
  Future<void> completeSession(String sessionId) => throw UnimplementedError();
}

/// Minimal [StoryRepository] that returns a configurable library.
class _FakeStoryRepository implements StoryRepository {
  _FakeStoryRepository({List<Story> library = const []}) : _library = library;

  final List<Story> _library;

  @override
  Future<List<Story>> getLibrary({AgeBand? ageBand, String? language}) async =>
      _library;

  @override
  Future<StoryDetail?> getStory(String storyId) async => null;
}

/// Minimal [ProfileRepository] that returns null profile (not under test).
class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<ChildProfile?> getProfile() async => null;

  @override
  Future<void> saveProfile(ChildProfile profile) async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

InteractionEvent _questionEvent({
  required String id,
  required String sessionId,
  required bool isCorrect,
}) =>
    InteractionEvent(
      id: id,
      storySessionId: sessionId,
      eventType: 'question_answered',
      payload: {'is_correct': isCorrect},
      createdAt: DateTime(2026, 6, 18),
    );

StorySession _completedSession({required String id, required String storyId}) =>
    StorySession(
      id: id,
      childProfileId: 'child-1',
      storyId: storyId,
      startedAt: DateTime(2026, 6, 18, 10),
      completedAt: DateTime(2026, 6, 18, 11),
      mode: SessionMode.library,
    );

Story _story({required String id}) =>
    Story(id: id, title: 'Story $id', slug: 'story-$id');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('dashboardSummaryProvider – question metrics fan-out', () {
    test(
        'counts questions answered/correct across MORE THAN ONE session '
        '(fails under old getEvents()-with-no-arg, passes after fan-out fix)',
        () async {
      // Two sessions, each with their own question_answered events.
      const sess1Id = 'sess-1';
      const sess2Id = 'sess-2';

      final sessions = [
        _completedSession(id: sess1Id, storyId: 'story-a'),
        _completedSession(id: sess2Id, storyId: 'story-b'),
      ];

      final eventsBySession = {
        sess1Id: [
          _questionEvent(id: 'e1', sessionId: sess1Id, isCorrect: true),
          _questionEvent(id: 'e2', sessionId: sess1Id, isCorrect: false),
        ],
        sess2Id: [
          _questionEvent(id: 'e3', sessionId: sess2Id, isCorrect: true),
          _questionEvent(id: 'e4', sessionId: sess2Id, isCorrect: true),
          _questionEvent(id: 'e5', sessionId: sess2Id, isCorrect: false),
        ],
      };

      final container = ProviderContainer(
        overrides: [
          // profileRepositoryProvider must be overridden so childProfileProvider
          // can resolve without a real KeyValueStore / HTTP client.
          profileRepositoryProvider
              .overrideWithValue(_FakeProfileRepository()),
          // childProfileProvider: return null (no profile filter needed).
          childProfileProvider.overrideWith(() => _NullChildProfileNotifier()),
          sessionRepositoryProvider.overrideWithValue(
            _FakeSessionRepository(
              sessions: sessions,
              eventsBySession: eventsBySession,
            ),
          ),
          storyRepositoryProvider.overrideWithValue(_FakeStoryRepository()),
        ],
      );
      addTearDown(container.dispose);

      // Pre-warm childProfileProvider so it is in AsyncData before the
      // dashboardSummaryProvider starts watching it. Without this, the
      // dashboard provider would restart when childProfileProvider transitions
      // loading → data, causing its own in-flight future to be cancelled and
      // creating an infinite loop.
      await container.read(childProfileProvider.future);

      final state = await container.read(dashboardStateProvider.future);

      // 5 total question_answered events across both sessions.
      expect(state.summary.questionsAnswered, 5,
          reason: 'must fan-out getEvents() per session, not call with no arg');

      // 3 correct (e1, e3, e4).
      expect(state.summary.questionsCorrect, 3);

      // accuracy = 3/5.
      expect(state.summary.questionAccuracy, closeTo(0.6, 0.001));
    });
  });

  group('dashboardStateProvider – privacy-aware states (§14)', () {
    Future<(ProviderContainer, _FakeSessionRepository)> makeContainer({
      required bool trackingEnabled,
      _FakeSessionRepository? sessionRepo,
      List<Story> library = const [],
    }) async {
      final repo = sessionRepo ?? _FakeSessionRepository();
      final container = ProviderContainer(
        // Riverpod 3 auto-retries failed builds with real timers; disable that
        // so error-path tests resolve immediately.
        retry: (_, _) => null,
        overrides: [
          profileRepositoryProvider
              .overrideWithValue(_FakeProfileRepository()),
          childProfileProvider.overrideWith(() => _NullChildProfileNotifier()),
          effectiveProgressTrackingProvider.overrideWithValue(trackingEnabled),
          sessionRepositoryProvider.overrideWithValue(repo),
          storyRepositoryProvider.overrideWithValue(
            _FakeStoryRepository(library: library),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Pre-warm childProfileProvider (see the fan-out test above).
      await container.read(childProfileProvider.future);
      return (container, repo);
    }

    test('trackingOnWithHistory: tracking on + sessions → live stats',
        () async {
      final sessions = [_completedSession(id: 'sess-1', storyId: 'story-a')];
      final (container, _) = await makeContainer(
        trackingEnabled: true,
        sessionRepo: _FakeSessionRepository(
          sessions: sessions,
          eventsBySession: {
            'sess-1': [
              _questionEvent(id: 'e1', sessionId: 'sess-1', isCorrect: true),
            ],
          },
        ),
        library: [_story(id: 'story-a'), _story(id: 'story-b')],
      );

      final state = await container.read(dashboardStateProvider.future);

      expect(state.status, DashboardTrackingStatus.trackingOnWithHistory);
      expect(state.summary.storiesCompleted, 1);
      expect(state.summary.questionsAnswered, 1);
      expect(state.summary.recentStories.map((s) => s.id), ['story-a']);
      // Recommendations stay available: only the completed story is excluded.
      expect(state.summary.recommended.map((s) => s.id), ['story-b']);
    });

    test('trackingOnNoHistory: tracking on + no sessions → empty, '
        'recommendations still available', () async {
      final (container, _) = await makeContainer(
        trackingEnabled: true,
        library: [_story(id: 'story-a')],
      );

      final state = await container.read(dashboardStateProvider.future);

      expect(state.status, DashboardTrackingStatus.trackingOnNoHistory);
      expect(state.summary.storiesCompleted, 0);
      expect(state.summary.recentStories, isEmpty);
      expect(state.summary.recommended.map((s) => s.id), ['story-a']);
    });

    test('trackingOffNoHistory: tracking off + no sessions', () async {
      final (container, _) = await makeContainer(
        trackingEnabled: false,
        library: [_story(id: 'story-a')],
      );

      final state = await container.read(dashboardStateProvider.future);

      expect(state.status, DashboardTrackingStatus.trackingOffNoHistory);
      expect(state.summary.recentStories, isEmpty);
      // Library recommendations remain available in every state.
      expect(state.summary.recommended.map((s) => s.id), ['story-a']);
    });

    test('trackingOffRetainedHistory: tracking off + retained sessions '
        '(retained reads stay readable, no live-tracking claim)', () async {
      final sessions = [_completedSession(id: 'sess-1', storyId: 'story-a')];
      final (container, _) = await makeContainer(
        trackingEnabled: false,
        sessionRepo: _FakeSessionRepository(
          sessions: sessions,
          eventsBySession: {
            'sess-1': [
              _questionEvent(id: 'e1', sessionId: 'sess-1', isCorrect: false),
            ],
          },
        ),
        library: [_story(id: 'story-a'), _story(id: 'story-b')],
      );

      final state = await container.read(dashboardStateProvider.future);

      expect(state.status, DashboardTrackingStatus.trackingOffRetainedHistory);
      expect(state.summary.storiesCompleted, 1);
      expect(state.summary.recentStories.map((s) => s.id), ['story-a']);
      expect(state.summary.recommended, isNotEmpty);
    });

    test(
        'remote session-list error surfaces as an error, never as empty '
        'history', () async {
      final (container, _) = await makeContainer(
        trackingEnabled: true,
        sessionRepo: _FakeSessionRepository(
          getSessionsError: const SessionFailure('network'),
        ),
      );

      await expectLater(
        container.read(dashboardStateProvider.future),
        throwsA(isA<SessionFailure>()
            .having((e) => e.code, 'code', 'network')),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal ChildProfileNotifier stub (returns null — no profile filter)
// ---------------------------------------------------------------------------

class _NullChildProfileNotifier extends ChildProfileNotifier {
  @override
  Future<ChildProfile?> build() async => null;
}
