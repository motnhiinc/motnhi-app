// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_target_manifest.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ImageTarget _$ImageTargetFromJson(Map<String, dynamic> json) => _ImageTarget(
  pageId: json['page_id'] as String,
  pageNumber: (json['page_number'] as num).toInt(),
  imageTargetId: json['image_target_id'] as String,
  referenceImageUrl: json['reference_image_url'] as String?,
  physicalWidthMm: (json['physical_width_mm'] as num).toInt(),
);

Map<String, dynamic> _$ImageTargetToJson(_ImageTarget instance) =>
    <String, dynamic>{
      'page_id': instance.pageId,
      'page_number': instance.pageNumber,
      'image_target_id': instance.imageTargetId,
      'reference_image_url': instance.referenceImageUrl,
      'physical_width_mm': instance.physicalWidthMm,
    };

_ImageTargetManifest _$ImageTargetManifestFromJson(Map<String, dynamic> json) =>
    _ImageTargetManifest(
      storyId: json['story_id'] as String,
      version: (json['version'] as num).toInt(),
      targets:
          (json['targets'] as List<dynamic>?)
              ?.map((e) => ImageTarget.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <ImageTarget>[],
    );

Map<String, dynamic> _$ImageTargetManifestToJson(
  _ImageTargetManifest instance,
) => <String, dynamic>{
  'story_id': instance.storyId,
  'version': instance.version,
  'targets': instance.targets.map((e) => e.toJson()).toList(),
};
