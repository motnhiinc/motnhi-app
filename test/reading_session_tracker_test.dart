import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/session_repository.dart';
import 'package:storybook_ar/features/player/reading_session_tracker.dart';

class _FakeSessionRepository implements SessionRepository {
  final calls = <String>[];
  final lastPages = <({String sessionId, int pageNumber})>[];
  final completions = <String>[];
  final events =
      <({String sessionId, String eventType, String? pageId, Map<String, dynamic> payload})>[];

  Object? startError;
  Object? pageError;
  Object? questionError;
  Object? completeError;

  @override
  Future<StorySession> startSession({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) async {
    calls.add('start');
    final error = startError;
    if (error != null) throw error;
    return StorySession(
      id: 'sess1',
      childProfileId: childProfileId,
      storyId: storyId,
      startedAt: DateTime.utc(2026, 9, 1),
      mode: mode,
    );
  }

  @override
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String? pageId,
    Map<String, dynamic> payload = const {},
  }) async {
    calls.add('recordEvent:$eventType');
    final error = eventType == 'question_answered' ? questionError : null;
    if (error != null) throw error;
    events.add((
      sessionId: sessionId,
      eventType: eventType,
      pageId: pageId,
      payload: payload,
    ));
  }

  @override
  Future<void> updateLastPage(String sessionId, int pageNumber) async {
    calls.add('updateLastPage');
    final error = pageError;
    if (error != null) throw error;
    lastPages.add((sessionId: sessionId, pageNumber: pageNumber));
  }

  @override
  Future<void> completeSession(String sessionId) async {
    calls.add('complete');
    final error = completeError;
    if (error != null) throw error;
    completions.add(sessionId);
  }

  @override
  Future<List<StorySession>> getSessions({String? childProfileId}) async => [];

  @override
  Future<List<InteractionEvent>> getEvents({String? sessionId}) async => [];
}

void main() {
  group('ReadingSessionTracker', () {
    test('disabled startup: all methods are no-ops with no repository calls',
        () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: false);

      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.bedtime);
      await tracker.pageViewed(pageId: 'page1', pageNumber: 1, mode: 'bedtime');
      await tracker.questionAnswered(
          pageId: 'page1', questionId: 'q1', answerId: 'a1', isCorrect: true);
      await tracker.complete();

      expect(repo.calls, isEmpty);
      expect(tracker.sessionId, isNull);
      expect(tracker.writesDisabled, isFalse);
    });

    test('enabled startup: start stores the session id', () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);

      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.bedtime);

      expect(tracker.sessionId, 'sess1');
      expect(tracker.writesDisabled, isFalse);
      expect(repo.calls, ['start']);
      expect(repo.lastPages, isEmpty);
    });

    test('pageViewed writes last page and records a page_viewed event',
        () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.bedtime);

      await tracker.pageViewed(pageId: 'page3', pageNumber: 3, mode: 'bedtime');

      expect(repo.lastPages.single,
          (sessionId: 'sess1', pageNumber: 3));
      expect(repo.events.single.eventType, 'page_viewed');
      expect(repo.events.single.pageId, 'page3');
      expect(repo.events.single.payload, {
        'page_number': 3,
        'mode': 'bedtime',
      });
      expect(repo.events.single.sessionId, 'sess1');
    });

    test('pageViewed omits mode from the payload when not provided', () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);

      await tracker.pageViewed(pageId: 'page2', pageNumber: 2);

      expect(repo.events.single.payload, {'page_number': 2});
    });

    test('questionAnswered records a question_answered event with the payload',
        () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);

      await tracker.questionAnswered(
          pageId: 'page4', questionId: 'q1', answerId: 'a2', isCorrect: false);

      expect(repo.calls, ['start', 'recordEvent:question_answered']);
      expect(repo.events.single.eventType, 'question_answered');
      expect(repo.events.single.pageId, 'page4');
      expect(repo.events.single.payload, {
        'question_id': 'q1',
        'answer_id': 'a2',
        'is_correct': false,
      });
    });

    test('complete marks the session completed', () async {
      final repo = _FakeSessionRepository();
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);

      await tracker.complete();

      expect(repo.completions, ['sess1']);
    });

    test(
        'start rejection (progress_tracking_disabled) clears sessionId, disables writes, does not throw',
        () async {
      final repo = _FakeSessionRepository()
        ..startError =
            const SessionFailure('progress_tracking_disabled');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);

      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.bedtime);

      expect(tracker.sessionId, isNull);
      expect(tracker.writesDisabled, isTrue);

      await tracker.pageViewed(pageId: 'page1', pageNumber: 1);
      await tracker.questionAnswered(
          pageId: 'page1', questionId: 'q1', answerId: 'a1', isCorrect: true);
      await tracker.complete();

      expect(repo.calls, ['start']);
      expect(repo.lastPages, isEmpty);
      expect(repo.completions, isEmpty);
    });

    test(
        'mid-session rejection disables writes, clears sessionId, and does not rethrow',
        () async {
      final repo = _FakeSessionRepository()
        ..pageError = const SessionFailure('progress_tracking_disabled');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.bedtime);

      await tracker.pageViewed(pageId: 'page1', pageNumber: 1);

      expect(tracker.writesDisabled, isTrue);
      expect(tracker.sessionId, isNull);

      // Subsequent writes are suppressed and never reach the repository.
      await tracker.questionAnswered(
          pageId: 'page1', questionId: 'q1', answerId: 'a1', isCorrect: true);
      await tracker.pageViewed(pageId: 'page2', pageNumber: 2);
      await tracker.complete();

      expect(repo.lastPages, isEmpty);
      expect(repo.events, isEmpty);
      expect(repo.completions, isEmpty);
    });

    test('mid-session question rejection also disables writes', () async {
      final repo = _FakeSessionRepository()
        ..questionError = const SessionFailure('progress_tracking_disabled');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);

      await tracker.questionAnswered(
          pageId: 'page1', questionId: 'q1', answerId: 'a1', isCorrect: true);

      expect(tracker.writesDisabled, isTrue);
      expect(tracker.sessionId, isNull);
    });

    test('non-consent failure from start rethrows', () async {
      final repo = _FakeSessionRepository()
        ..startError = const SessionFailure('network');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);

      await expectLater(
        tracker.start(
            childProfileId: 'p1', storyId: 's1', mode: SessionMode.library),
        throwsA(isA<SessionFailure>()
            .having((e) => e.code, 'code', 'network')),
      );
      expect(tracker.sessionId, isNull);
      expect(tracker.writesDisabled, isFalse);
    });

    test('non-consent failure after reading has begun is suppressed',
        () async {
      final repo = _FakeSessionRepository()
        ..pageError = const SessionFailure('network');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);

      await tracker.pageViewed(pageId: 'page1', pageNumber: 1);

      expect(tracker.sessionId, 'sess1');
      expect(tracker.writesDisabled, isFalse);

      // Reading continues; the next write still goes to the repository.
      repo.pageError = null;
      await tracker.pageViewed(pageId: 'page2', pageNumber: 2);
      expect(repo.lastPages.last, (sessionId: 'sess1', pageNumber: 2));
    });

    test(
        'permanent suppression after the first progress rejection: later calls are no-ops',
        () async {
      final repo = _FakeSessionRepository()
        ..startError = const SessionFailure('progress_tracking_disabled');
      final tracker = ReadingSessionTracker(repository: repo, trackingEnabled: true);

      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);
      // Even if the repository would now succeed, writes stay disabled.
      repo.startError = null;
      await tracker.start(
          childProfileId: 'p1', storyId: 's1', mode: SessionMode.library);
      await tracker.pageViewed(pageId: 'page1', pageNumber: 1);
      await tracker.questionAnswered(
          pageId: 'page1', questionId: 'q1', answerId: 'a1', isCorrect: true);
      await tracker.complete();

      expect(repo.calls, ['start']);
      expect(tracker.sessionId, isNull);
      expect(tracker.writesDisabled, isTrue);
    });
  });
}
