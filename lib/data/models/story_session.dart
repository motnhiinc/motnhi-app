import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'story_session.freezed.dart';
part 'story_session.g.dart';

/// A reading session (§10 `story_sessions`). Runtime telemetry, per child.
/// `completed_at` stays null until the story finishes (completion metric §16.1);
/// `last_page_number` carries resume state (§9.5.6).
@freezed
abstract class StorySession with _$StorySession {
  const StorySession._();

  const factory StorySession({
    required String id,
    required String childProfileId,
    required String storyId,
    required DateTime startedAt,
    DateTime? completedAt,
    @Default(0) int lastPageNumber,
    @Default(SessionMode.library) SessionMode mode,
  }) = _StorySession;

  factory StorySession.fromJson(Map<String, dynamic> json) =>
      _$StorySessionFromJson(json);

  bool get isCompleted => completedAt != null;

  Duration? get readingTime => completedAt?.difference(startedAt);
}
