import '../models/models.dart';
import '../sources/key_value_store.dart';

/// Stores the child profile and onboarding/consent state (§9.5.2, §7.2.1).
/// One implicit local parent in this slice.
abstract class ProfileRepository {
  Future<ChildProfile?> getProfile();
  Future<void> saveProfile(ChildProfile profile);

  /// Parent consent recorded during onboarding (§14.2).
  bool get hasConsented;
  Future<void> setConsented(bool value);

  bool get isOnboarded;
}

class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository(this._store);

  final KeyValueStore _store;

  static const _profileKey = 'child_profile';
  static const _consentKey = 'parent_consent';

  @override
  Future<ChildProfile?> getProfile() async {
    final json = _store.readJson(_profileKey);
    if (json == null) return null;
    return ChildProfile.fromJson(json);
  }

  @override
  Future<void> saveProfile(ChildProfile profile) =>
      _store.writeJson(_profileKey, profile.toJson());

  @override
  bool get hasConsented => _store.getBool(_consentKey);

  @override
  Future<void> setConsented(bool value) => _store.setBool(_consentKey, value);

  @override
  bool get isOnboarded =>
      hasConsented && _store.readJson(_profileKey) != null;
}
