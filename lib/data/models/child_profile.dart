import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'child_profile.freezed.dart';
part 'child_profile.g.dart';

/// A child profile (§10 `child_profiles`). Data-minimized by design (§14.3):
/// nickname not legal name, age band not birthdate, no child photo. Microphone
/// is **off by default**; AR is gated by parent permission.
@freezed
abstract class ChildProfile with _$ChildProfile {
  const factory ChildProfile({
    required String id,

    /// FK → `users.id`. Single implicit local parent in this offline slice.
    @Default('local-parent') String userId,
    String? nickname,
    required AgeBand ageBand,
    @Default('en') String languageCode,
    @Default(false) bool bedtimeModeDefault,
    @Default(false) bool microphoneEnabled,
    @Default(true) bool arEnabled,
  }) = _ChildProfile;

  factory ChildProfile.fromJson(Map<String, dynamic> json) =>
      _$ChildProfileFromJson(json);
}
