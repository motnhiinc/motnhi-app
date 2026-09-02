import '../models/models.dart';
import '../sources/key_value_store.dart';

/// Stores the child profile (§9.5.2, §7.2.1). One implicit local parent in
/// this slice. Consent and privacy choices live in privacy state (§14), not
/// here.
abstract class ProfileRepository {
  Future<ChildProfile?> getProfile();
  Future<void> saveProfile(ChildProfile profile);
}

/// Typed profile failure. [code] is the backend `detail` when the server sent
/// one (e.g. `privacy_policy_review_required`), otherwise a client-side
/// classification (`network`, `invalid_response`).
final class ProfileFailure implements Exception {
  const ProfileFailure(this.code);

  final String code;

  @override
  String toString() => 'ProfileFailure($code)';
}

class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository(this._store);

  final KeyValueStore _store;

  static const _profileKey = 'child_profile';

  @override
  Future<ChildProfile?> getProfile() async {
    final json = _store.readJson(_profileKey);
    if (json == null) return null;
    return ChildProfile.fromJson(json);
  }

  @override
  Future<void> saveProfile(ChildProfile profile) =>
      _store.writeJson(_profileKey, profile.toJson());
}
