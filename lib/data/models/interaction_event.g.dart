// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_InteractionEvent _$InteractionEventFromJson(Map<String, dynamic> json) =>
    _InteractionEvent(
      id: json['id'] as String,
      storySessionId: json['story_session_id'] as String,
      eventType: json['event_type'] as String,
      pageId: json['page_id'] as String?,
      payload:
          json['payload'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$InteractionEventToJson(_InteractionEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'story_session_id': instance.storySessionId,
      'event_type': instance.eventType,
      'page_id': instance.pageId,
      'payload': instance.payload,
      'created_at': instance.createdAt.toIso8601String(),
    };
