// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ar_scene.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ArVector3 _$ArVector3FromJson(Map<String, dynamic> json) => _ArVector3(
  x: (json['x'] as num?)?.toDouble() ?? 0.0,
  y: (json['y'] as num?)?.toDouble() ?? 0.0,
  z: (json['z'] as num?)?.toDouble() ?? 0.0,
);

Map<String, dynamic> _$ArVector3ToJson(_ArVector3 instance) =>
    <String, dynamic>{'x': instance.x, 'y': instance.y, 'z': instance.z};

_ArSceneAsset _$ArSceneAssetFromJson(Map<String, dynamic> json) =>
    _ArSceneAsset(
      assetId: json['asset_id'] as String,
      type: $enumDecode(_$ArAssetTypeEnumMap, json['type']),
      position: json['position'] == null
          ? const ArVector3()
          : ArVector3.fromJson(json['position'] as Map<String, dynamic>),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      defaultAnimation: json['default_animation'] as String,
      imageAsset: json['image_asset'] as String?,
    );

Map<String, dynamic> _$ArSceneAssetToJson(_ArSceneAsset instance) =>
    <String, dynamic>{
      'asset_id': instance.assetId,
      'type': _$ArAssetTypeEnumMap[instance.type]!,
      'position': instance.position.toJson(),
      'scale': instance.scale,
      'default_animation': instance.defaultAnimation,
      'image_asset': instance.imageAsset,
    };

const _$ArAssetTypeEnumMap = {
  ArAssetType.character2d: '2d_character',
  ArAssetType.object2d: '2d_object',
  ArAssetType.character3d: '3d_character',
};

_ArInteraction _$ArInteractionFromJson(Map<String, dynamic> json) =>
    _ArInteraction(
      trigger: $enumDecode(_$ArTriggerEnumMap, json['trigger']),
      targetAssetId: json['target_asset_id'] as String,
      action: $enumDecode(_$ArActionEnumMap, json['action']),
      audioSegmentId: json['audio_segment_id'] as String?,
    );

Map<String, dynamic> _$ArInteractionToJson(_ArInteraction instance) =>
    <String, dynamic>{
      'trigger': _$ArTriggerEnumMap[instance.trigger]!,
      'target_asset_id': instance.targetAssetId,
      'action': _$ArActionEnumMap[instance.action]!,
      'audio_segment_id': instance.audioSegmentId,
    };

const _$ArTriggerEnumMap = {ArTrigger.tap: 'tap', ArTrigger.auto: 'auto'};

const _$ArActionEnumMap = {
  ArAction.playAudioSegment: 'play_audio_segment',
  ArAction.playAnimation: 'play_animation',
};

_ArSceneData _$ArSceneDataFromJson(Map<String, dynamic> json) => _ArSceneData(
  sceneId: json['scene_id'] as String,
  anchorType:
      $enumDecodeNullable(_$ArAnchorTypeEnumMap, json['anchor_type']) ??
      ArAnchorType.imageTarget,
  assets:
      (json['assets'] as List<dynamic>?)
          ?.map((e) => ArSceneAsset.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ArSceneAsset>[],
  interactions:
      (json['interactions'] as List<dynamic>?)
          ?.map((e) => ArInteraction.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ArInteraction>[],
);

Map<String, dynamic> _$ArSceneDataToJson(_ArSceneData instance) =>
    <String, dynamic>{
      'scene_id': instance.sceneId,
      'anchor_type': _$ArAnchorTypeEnumMap[instance.anchorType]!,
      'assets': instance.assets.map((e) => e.toJson()).toList(),
      'interactions': instance.interactions.map((e) => e.toJson()).toList(),
    };

const _$ArAnchorTypeEnumMap = {
  ArAnchorType.imageTarget: 'image_target',
  ArAnchorType.plane: 'plane',
};

_ArScene _$ArSceneFromJson(Map<String, dynamic> json) => _ArScene(
  id: json['id'] as String,
  storyId: json['story_id'] as String,
  pageId: json['page_id'] as String,
  sceneJson: ArSceneData.fromJson(json['scene_json'] as Map<String, dynamic>),
  status:
      $enumDecodeNullable(_$ContentStatusEnumMap, json['status']) ??
      ContentStatus.published,
);

Map<String, dynamic> _$ArSceneToJson(_ArScene instance) => <String, dynamic>{
  'id': instance.id,
  'story_id': instance.storyId,
  'page_id': instance.pageId,
  'scene_json': instance.sceneJson.toJson(),
  'status': _$ContentStatusEnumMap[instance.status]!,
};

const _$ContentStatusEnumMap = {
  ContentStatus.draft: 'draft',
  ContentStatus.review: 'review',
  ContentStatus.published: 'published',
  ContentStatus.archived: 'archived',
};
