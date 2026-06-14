// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'child_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChildProfile _$ChildProfileFromJson(Map<String, dynamic> json) =>
    _ChildProfile(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? 'local-parent',
      nickname: json['nickname'] as String?,
      ageBand: $enumDecode(_$AgeBandEnumMap, json['age_band']),
      languageCode: json['language_code'] as String? ?? 'en',
      bedtimeModeDefault: json['bedtime_mode_default'] as bool? ?? false,
      microphoneEnabled: json['microphone_enabled'] as bool? ?? false,
      arEnabled: json['ar_enabled'] as bool? ?? true,
    );

Map<String, dynamic> _$ChildProfileToJson(_ChildProfile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'nickname': instance.nickname,
      'age_band': _$AgeBandEnumMap[instance.ageBand]!,
      'language_code': instance.languageCode,
      'bedtime_mode_default': instance.bedtimeModeDefault,
      'microphone_enabled': instance.microphoneEnabled,
      'ar_enabled': instance.arEnabled,
    };

const _$AgeBandEnumMap = {
  AgeBand.threeToFour: '3-4',
  AgeBand.fiveToSix: '5-6',
  AgeBand.sevenToEight: '7-8',
};
