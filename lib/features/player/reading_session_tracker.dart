import '../../data/models/models.dart';
import '../../data/repositories/session_repository.dart';

/// The server detail code returned when a parent revoked progress-tracking
/// consent (§14 consent enforcement on the session write endpoints).
const _progressTrackingDisabled = 'progress_tracking_disabled';

/// Keeps story reading usable while session telemetry is written in the
/// background. A consent revocation mid-story (`progress_tracking_disabled`)
/// permanently disables writes and is swallowed; other failures are also
/// suppressed once reading has begun, so they never interrupt the child.
class ReadingSessionTracker {
  ReadingSessionTracker({
    required SessionRepository repository,
    required bool trackingEnabled,
  })  : _repository = repository,
        _trackingEnabled = trackingEnabled;

  final SessionRepository _repository;
  final bool _trackingEnabled;

  String? _sessionId;
  bool _writesDisabled = false;

  String? get sessionId => _sessionId;
  bool get writesDisabled => _writesDisabled;

  Future<void> start({
    required String childProfileId,
    required String storyId,
    required SessionMode mode,
  }) async {
    if (!_trackingEnabled || _writesDisabled) return;
    try {
      final session = await _repository.startSession(
        childProfileId: childProfileId,
        storyId: storyId,
        mode: mode,
      );
      _sessionId = session.id;
    } on SessionFailure catch (error) {
      if (error.code == _progressTrackingDisabled) {
        _disableWrites();
        return;
      }
      rethrow;
    }
  }

  Future<void> pageViewed({
    required String pageId,
    required int pageNumber,
    String? mode,
  }) async {
    if (!_trackingEnabled || _writesDisabled || _sessionId == null) return;
    final sessionId = _sessionId!;
    try {
      await _repository.updateLastPage(sessionId, pageNumber);
      await _repository.recordEvent(
        sessionId: sessionId,
        eventType: 'page_viewed',
        pageId: pageId,
        payload: {
          'page_number': pageNumber,
          'mode': ?mode,
        },
      );
    } on SessionFailure catch (error) {
      if (error.code == _progressTrackingDisabled) {
        _disableWrites();
      }
    }
  }

  Future<void> questionAnswered({
    required String pageId,
    required String questionId,
    required String answerId,
    required bool isCorrect,
  }) async {
    if (!_trackingEnabled || _writesDisabled || _sessionId == null) return;
    final sessionId = _sessionId!;
    try {
      await _repository.recordEvent(
        sessionId: sessionId,
        eventType: 'question_answered',
        pageId: pageId,
        payload: {
          'question_id': questionId,
          'answer_id': answerId,
          'is_correct': isCorrect,
        },
      );
    } on SessionFailure catch (error) {
      if (error.code == _progressTrackingDisabled) {
        _disableWrites();
      }
    }
  }

  Future<void> complete() async {
    if (!_trackingEnabled || _writesDisabled || _sessionId == null) return;
    final sessionId = _sessionId!;
    try {
      await _repository.completeSession(sessionId);
    } on SessionFailure catch (error) {
      if (error.code == _progressTrackingDisabled) {
        _disableWrites();
      }
    }
  }

  void _disableWrites() {
    _writesDisabled = true;
    _sessionId = null;
  }
}
