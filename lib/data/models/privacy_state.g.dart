// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'privacy_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PrivacyDataCounts _$PrivacyDataCountsFromJson(Map<String, dynamic> json) =>
    _PrivacyDataCounts(
      childProfiles: (json['child_profiles'] as num?)?.toInt() ?? 0,
      authoredStories: (json['authored_stories'] as num?)?.toInt() ?? 0,
      storySessions: (json['story_sessions'] as num?)?.toInt() ?? 0,
      interactionEvents: (json['interaction_events'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$PrivacyDataCountsToJson(_PrivacyDataCounts instance) =>
    <String, dynamic>{
      'child_profiles': instance.childProfiles,
      'authored_stories': instance.authoredStories,
      'story_sessions': instance.storySessions,
      'interaction_events': instance.interactionEvents,
    };

_PrivacyState _$PrivacyStateFromJson(Map<String, dynamic> json) =>
    _PrivacyState(
      currentPolicyVersion: json['current_policy_version'] as String,
      acceptedPolicyVersion: json['accepted_policy_version'] as String?,
      reviewRequired: json['review_required'] as bool,
      coreStorageAcceptedAt: json['core_storage_accepted_at'] == null
          ? null
          : DateTime.parse(json['core_storage_accepted_at'] as String),
      progressTrackingEnabled:
          json['progress_tracking_enabled'] as bool? ?? false,
      cloudTtsEnabled: json['cloud_tts_enabled'] as bool? ?? false,
      pageImageValidationEnabled:
          json['page_image_validation_enabled'] as bool? ?? false,
      effectiveProgressTrackingEnabled:
          json['effective_progress_tracking_enabled'] as bool? ?? false,
      effectiveCloudTtsEnabled:
          json['effective_cloud_tts_enabled'] as bool? ?? false,
      effectivePageImageValidationEnabled:
          json['effective_page_image_validation_enabled'] as bool? ?? false,
      lastActiveAt: DateTime.parse(json['last_active_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      counts: json['counts'] == null
          ? const PrivacyDataCounts()
          : PrivacyDataCounts.fromJson(json['counts'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PrivacyStateToJson(
  _PrivacyState instance,
) => <String, dynamic>{
  'current_policy_version': instance.currentPolicyVersion,
  'accepted_policy_version': instance.acceptedPolicyVersion,
  'review_required': instance.reviewRequired,
  'core_storage_accepted_at': instance.coreStorageAcceptedAt?.toIso8601String(),
  'progress_tracking_enabled': instance.progressTrackingEnabled,
  'cloud_tts_enabled': instance.cloudTtsEnabled,
  'page_image_validation_enabled': instance.pageImageValidationEnabled,
  'effective_progress_tracking_enabled':
      instance.effectiveProgressTrackingEnabled,
  'effective_cloud_tts_enabled': instance.effectiveCloudTtsEnabled,
  'effective_page_image_validation_enabled':
      instance.effectivePageImageValidationEnabled,
  'last_active_at': instance.lastActiveAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'counts': instance.counts.toJson(),
};
