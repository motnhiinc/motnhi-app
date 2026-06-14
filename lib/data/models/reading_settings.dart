import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_settings.freezed.dart';
part 'reading_settings.g.dart';

/// Parent-controlled reading settings (§7.2.4). Local-only client preferences,
/// kept separate from the data-minimized `child_profiles` row.
@freezed
abstract class ReadingSettings with _$ReadingSettings {
  const ReadingSettings._();

  const factory ReadingSettings({
    /// Narration speed multiplier applied on top of per-segment speed.
    @Default(1.0) double voiceSpeed,
    @Default(0.6) double soundEffectsVolume,
    @Default(0.4) double backgroundMusicVolume,
    @Default('en') String languageCode,
    @Default(false) bool bedtimeModeDefault,
  }) = _ReadingSettings;

  factory ReadingSettings.fromJson(Map<String, dynamic> json) =>
      _$ReadingSettingsFromJson(json);

  /// Bedtime profile (§7.1.6, §9.4.3): slower narration, lower SFX/music.
  ReadingSettings get bedtimeProfile => copyWith(
        voiceSpeed: (voiceSpeed * 0.85).clamp(0.5, 1.2),
        soundEffectsVolume: soundEffectsVolume * 0.4,
        backgroundMusicVolume: backgroundMusicVolume * 0.5,
      );
}
