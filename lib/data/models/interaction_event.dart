import 'package:freezed_annotation/freezed_annotation.dart';

part 'interaction_event.freezed.dart';
part 'interaction_event.g.dart';

/// A telemetry event within a session (§10 `interaction_events`, §11.4).
/// Feeds the analytics metrics (§16); `payload` holds event-specific data such
/// as `question_id`/`answer_id`/`is_correct`.
@freezed
abstract class InteractionEvent with _$InteractionEvent {
  const factory InteractionEvent({
    required String id,
    required String storySessionId,

    /// e.g. `story_started`, `page_viewed`, `question_answered`,
    /// `ar_interaction`, `story_completed` (§16.1 must-have events §8.3).
    required String eventType,
    String? pageId,
    @Default(<String, dynamic>{}) Map<String, dynamic> payload,
    required DateTime createdAt,
  }) = _InteractionEvent;

  factory InteractionEvent.fromJson(Map<String, dynamic> json) =>
      _$InteractionEventFromJson(json);
}
