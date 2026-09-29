import '../models/models.dart';

/// Parent-facing privacy & consent state (§14): policy acceptance, data
/// processing toggles, activity logging, and data deletion.
abstract interface class PrivacyRepository {
  Future<PrivacyState> fetchPrivacy();

  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
    required bool pageImageValidationEnabled,
  });

  /// Records that the child used the app (keeps [PrivacyState.lastActiveAt]
  /// fresh). Endpoint lands on the backend in a later task.
  Future<void> recordActivity();

  Future<void> deleteReadingHistory();

  Future<void> deleteChildData();
}

class PrivacyFailure implements Exception {
  const PrivacyFailure(this.code);

  final String code;
}
