import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'key_value_store.dart';

/// Wraps a [Dio] with anonymous device auth (spec §7): on first use it
/// generates+persists a device id, exchanges it for a JWT, and attaches the
/// JWT as a Bearer header.
///
/// 🔒 SECURITY AMENDMENT (device_secret): on first registration the server
/// returns a [device_secret] which is persisted locally. Every subsequent
/// /v1/auth/device call includes the stored secret so the server can verify
/// proof-of-possession. On 401, only the token is cleared (not the secret);
/// re-minting sends device_id + stored secret.
///
/// [authDio] is an optional separate [Dio] instance used for the
/// /v1/auth/device call. Injected so tests can mock it independently, avoiding
/// interceptor re-entrancy / deadlock. Defaults to a plain clone of [dio]
/// (same baseUrl, no interceptors added to it).
class ApiClient {
  ApiClient({
    required this.dio,
    required KeyValueStore store,
    Uuid? uuid,
    Dio? authDio,
  })  : _store = store,
        _uuid = uuid ?? const Uuid(),
        _authDio = authDio ?? Dio(BaseOptions(baseUrl: dio.options.baseUrl)) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          if (!options.path.endsWith('/v1/auth/device')) {
            final token = await _ensureToken();
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        } on DioException catch (error) {
          handler.reject(error);
        }
      },
    ));
  }

  final Dio dio;

  /// Separate Dio instance used only for /v1/auth/device to avoid interceptor
  /// re-entrancy / deadlock when refreshing the token from within a request.
  final Dio _authDio;

  final KeyValueStore _store;
  final Uuid _uuid;
  Future<String>? _tokenBootstrap;

  static const _deviceKey = 'device_id';
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user_id';
  static const _secretKey = 'device_secret';

  String? get userId => _store.getString(_userKey);

  Future<String> _deviceId() async {
    final existing = _store.getString(_deviceKey);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await _store.setString(_deviceKey, id);
    return id;
  }

  Future<String> _ensureToken() async {
    final cached = _store.getString(_tokenKey);
    if (cached != null) return cached;

    final inFlight = _tokenBootstrap;
    if (inFlight != null) return inFlight;

    final bootstrap = _bootstrapToken();
    _tokenBootstrap = bootstrap;
    try {
      return await bootstrap;
    } finally {
      _tokenBootstrap = null;
    }
  }

  Future<String> _bootstrapToken() async {
    final secret = _store.getString(_secretKey);
    final body = <String, dynamic>{'device_id': await _deviceId()};
    if (secret != null) body['device_secret'] = secret;

    final resp = await _authDio.post('/v1/auth/device', data: body);
    final token = resp.data['token'] as String;
    await _store.setString(_tokenKey, token);
    await _store.setString(_userKey, resp.data['user_id'] as String);

    final returnedSecret = resp.data['device_secret'];
    if (returnedSecret != null) {
      await _store.setString(_secretKey, returnedSecret as String);
    }

    return token;
  }

  /// Execute [request] with automatic 401 retry.
  ///
  /// On the first 401, the cached token is cleared and a fresh one is obtained
  /// (sending the stored device_secret). The request is then retried once.
  /// The device_secret is never cleared.
  Future<Response<T>> send<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _store.remove(_tokenKey);
        await _ensureToken();
        return await request();
      }
      rethrow;
    }
  }
}
