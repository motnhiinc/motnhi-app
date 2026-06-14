// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StorySession _$StorySessionFromJson(Map<String, dynamic> json) =>
    _StorySession(
      id: json['id'] as String,
      childProfileId: json['child_profile_id'] as String,
      storyId: json['story_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      lastPageNumber: (json['last_page_number'] as num?)?.toInt() ?? 0,
      mode:
          $enumDecodeNullable(_$SessionModeEnumMap, json['mode']) ??
          SessionMode.library,
    );

Map<String, dynamic> _$StorySessionToJson(_StorySession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'child_profile_id': instance.childProfileId,
      'story_id': instance.storyId,
      'started_at': instance.startedAt.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'last_page_number': instance.lastPageNumber,
      'mode': _$SessionModeEnumMap[instance.mode]!,
    };

const _$SessionModeEnumMap = {
  SessionMode.library: 'library',
  SessionMode.scan: 'scan',
  SessionMode.bedtime: 'bedtime',
  SessionMode.classroom: 'classroom',
};
