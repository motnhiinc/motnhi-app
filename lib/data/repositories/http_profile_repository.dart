import '../models/models.dart';
import '../sources/api_client.dart';
import '../sources/key_value_store.dart';
import 'profile_repository.dart';

/// HTTP implementation of [ProfileRepository]. Child profiles live server-side
/// (scoped to the device user); consent stays a local flag (§14.2).
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._api, this._store);

  final ApiClient _api;
  final KeyValueStore _store;

  static const _consentKey = 'parent_consent';

  @override
  Future<ChildProfile?> getProfile() async {
    final resp = await _api.dio.get('/v1/child-profiles');
    final list = (resp.data as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return ChildProfile.fromJson(list.first);
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {
    final body = profile.toJson()..remove('user_id'); // server sets user_id from JWT
    await _api.dio.post('/v1/child-profiles', data: body);
  }

  @override
  bool get hasConsented => _store.getBool(_consentKey);

  @override
  Future<void> setConsented(bool value) => _store.setBool(_consentKey, value);

  @override
  bool get isOnboarded => hasConsented && _store.getString('auth_user_id') != null;
}
