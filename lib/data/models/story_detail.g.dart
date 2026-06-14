// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StoryDetail _$StoryDetailFromJson(Map<String, dynamic> json) => _StoryDetail(
  story: Story.fromJson(json['story'] as Map<String, dynamic>),
  pages:
      (json['pages'] as List<dynamic>?)
          ?.map((e) => StoryPage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <StoryPage>[],
  segments:
      (json['segments'] as List<dynamic>?)
          ?.map((e) => NarrationSegment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <NarrationSegment>[],
  arScenes:
      (json['ar_scenes'] as List<dynamic>?)
          ?.map((e) => ArScene.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ArScene>[],
  questions:
      (json['questions'] as List<dynamic>?)
          ?.map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Question>[],
);

Map<String, dynamic> _$StoryDetailToJson(_StoryDetail instance) =>
    <String, dynamic>{
      'story': instance.story.toJson(),
      'pages': instance.pages.map((e) => e.toJson()).toList(),
      'segments': instance.segments.map((e) => e.toJson()).toList(),
      'ar_scenes': instance.arScenes.map((e) => e.toJson()).toList(),
      'questions': instance.questions.map((e) => e.toJson()).toList(),
    };
