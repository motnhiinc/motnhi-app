import 'package:freezed_annotation/freezed_annotation.dart';

part 'privacy_state.freezed.dart';
part 'privacy_state.g.dart';

/// Per-category data counts shown in the parent privacy screen (§14): a
/// transparency view of everything stored for this device.
@freezed
abstract class PrivacyDataCounts with _$PrivacyDataCounts {
  const factory PrivacyDataCounts({
    @Default(0) int childProfiles,
    @Default(0) int authoredStories,
    @Default(0) int storySessions,
    @Default(0) int interactionEvents,
  }) = _PrivacyDataCounts;

  factory PrivacyDataCounts.fromJson(Map<String, dynamic> json) =>
      _$PrivacyDataCountsFromJson(json);
}

/// Server-side privacy & consent state (§14): policy acceptance, data
/// processing toggles, and effective toggles after parent + kid gates.
@freezed
abstract class PrivacyState with _$PrivacyState {
  const factory PrivacyState({
    required String currentPolicyVersion,
    String? acceptedPolicyVersion,
    required bool reviewRequired,
    DateTime? coreStorageAcceptedAt,
    @Default(false) bool progressTrackingEnabled,
    @Default(false) bool cloudTtsEnabled,
    @Default(false) bool effectiveProgressTrackingEnabled,
    @Default(false) bool effectiveCloudTtsEnabled,
    required DateTime lastActiveAt,
    required DateTime updatedAt,
    @Default(PrivacyDataCounts()) PrivacyDataCounts counts,
  }) = _PrivacyState;

  factory PrivacyState.fromJson(Map<String, dynamic> json) =>
      _$PrivacyStateFromJson(json);
}
