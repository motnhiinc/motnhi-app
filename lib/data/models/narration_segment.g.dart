// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'narration_segment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NarrationSegment _$NarrationSegmentFromJson(Map<String, dynamic> json) =>
    _NarrationSegment(
      id: json['id'] as String,
      storyId: json['story_id'] as String,
      pageId: json['page_id'] as String,
      speakerKey: json['speaker_key'] as String,
      text: json['text'] as String,
      voiceId: json['voice_id'] as String,
      emotion: json['emotion'] as String?,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      audioAssetId: json['audio_asset_id'] as String?,
      startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
      endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sort_order'] as num).toInt(),
    );

Map<String, dynamic> _$NarrationSegmentToJson(_NarrationSegment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'story_id': instance.storyId,
      'page_id': instance.pageId,
      'speaker_key': instance.speakerKey,
      'text': instance.text,
      'voice_id': instance.voiceId,
      'emotion': instance.emotion,
      'speed': instance.speed,
      'audio_asset_id': instance.audioAssetId,
      'start_ms': instance.startMs,
      'end_ms': instance.endMs,
      'sort_order': instance.sortOrder,
    };
