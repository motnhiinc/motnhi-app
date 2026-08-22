// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Story _$StoryFromJson(Map<String, dynamic> json) => _Story(
  id: json['id'] as String,
  title: json['title'] as String,
  slug: json['slug'] as String,
  description: json['description'] as String?,
  ageMin: (json['age_min'] as num?)?.toInt() ?? 3,
  ageMax: (json['age_max'] as num?)?.toInt() ?? 8,
  languageCode: json['language_code'] as String? ?? 'en',
  durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
  coverAssetId: json['cover_asset_id'] as String?,
  contentStatus:
      $enumDecodeNullable(_$ContentStatusEnumMap, json['content_status']) ??
      ContentStatus.published,
  rightsOwnerId: json['rights_owner_id'] as String?,
  themes:
      (json['themes'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$StoryThemeEnumMap, e))
          .toList() ??
      const <StoryTheme>[],
  isDownloaded: json['is_downloaded'] as bool? ?? false,
  isUnlocked: json['is_unlocked'] as bool? ?? true,
  isAuthored: json['is_authored'] as bool? ?? false,
);

Map<String, dynamic> _$StoryToJson(_Story instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'slug': instance.slug,
  'description': instance.description,
  'age_min': instance.ageMin,
  'age_max': instance.ageMax,
  'language_code': instance.languageCode,
  'duration_seconds': instance.durationSeconds,
  'cover_asset_id': instance.coverAssetId,
  'content_status': _$ContentStatusEnumMap[instance.contentStatus]!,
  'rights_owner_id': instance.rightsOwnerId,
  'themes': instance.themes.map((e) => _$StoryThemeEnumMap[e]!).toList(),
  'is_downloaded': instance.isDownloaded,
  'is_unlocked': instance.isUnlocked,
  'is_authored': instance.isAuthored,
};

const _$ContentStatusEnumMap = {
  ContentStatus.draft: 'draft',
  ContentStatus.review: 'review',
  ContentStatus.published: 'published',
  ContentStatus.archived: 'archived',
};

const _$StoryThemeEnumMap = {
  StoryTheme.animals: 'animals',
  StoryTheme.bedtime: 'bedtime',
  StoryTheme.friendship: 'friendship',
  StoryTheme.emotions: 'emotions',
  StoryTheme.languageLearning: 'language_learning',
};
