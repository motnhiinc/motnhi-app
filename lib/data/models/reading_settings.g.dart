// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ReadingSettings _$ReadingSettingsFromJson(Map<String, dynamic> json) =>
    _ReadingSettings(
      voiceSpeed: (json['voice_speed'] as num?)?.toDouble() ?? 1.0,
      soundEffectsVolume:
          (json['sound_effects_volume'] as num?)?.toDouble() ?? 0.6,
      backgroundMusicVolume:
          (json['background_music_volume'] as num?)?.toDouble() ?? 0.4,
      languageCode: json['language_code'] as String? ?? 'en',
      bedtimeModeDefault: json['bedtime_mode_default'] as bool? ?? false,
    );

Map<String, dynamic> _$ReadingSettingsToJson(_ReadingSettings instance) =>
    <String, dynamic>{
      'voice_speed': instance.voiceSpeed,
      'sound_effects_volume': instance.soundEffectsVolume,
      'background_music_volume': instance.backgroundMusicVolume,
      'language_code': instance.languageCode,
      'bedtime_mode_default': instance.bedtimeModeDefault,
    };
