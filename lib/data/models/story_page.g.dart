// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StoryPage _$StoryPageFromJson(Map<String, dynamic> json) => _StoryPage(
  id: json['id'] as String,
  storyId: json['story_id'] as String,
  pageNumber: (json['page_number'] as num).toInt(),
  pageText: json['page_text'] as String?,
  pageImageAssetId: json['page_image_asset_id'] as String?,
  imageTargetId: json['image_target_id'] as String?,
);

Map<String, dynamic> _$StoryPageToJson(_StoryPage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'story_id': instance.storyId,
      'page_number': instance.pageNumber,
      'page_text': instance.pageText,
      'page_image_asset_id': instance.pageImageAssetId,
      'image_target_id': instance.imageTargetId,
    };
