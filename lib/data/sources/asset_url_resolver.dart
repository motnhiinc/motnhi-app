import 'package:dio/dio.dart';

import 'api_client.dart';

/// Resolves narration `audio_asset_id`s to playable, short-lived signed URLs
/// via `POST /v1/assets/sign` (spec §7.1, §9). Ids without a registered file
/// are omitted from the result so the player can fall back to TTS.
abstract class AssetUrlResolver {
  Future<Map<String, String>> resolve(List<String> assetIds);
}

class HttpAssetUrlResolver implements AssetUrlResolver {
  HttpAssetUrlResolver(this._api);

  final ApiClient _api;
  final Map<String, _Signed> _cache = {};

  /// Refresh URLs this many seconds before their `exp` to avoid races.
  static const _skewSeconds = 30;

  @override
  Future<Map<String, String>> resolve(List<String> assetIds) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = <String, String>{};
    final missing = <String>[];

    for (final id in assetIds.toSet()) {
      final cached = _cache[id];
      if (cached != null && cached.exp - _skewSeconds > now) {
        result[id] = cached.url;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return result;

    try {
      final resp = await _api.send(
        () => _api.dio.post('/v1/assets/sign', data: {'asset_ids': missing}),
      );
      final base = _api.dio.options.baseUrl;
      final map = (resp.data as Map).cast<String, dynamic>();
      map.forEach((id, rel) {
        final url = '$base$rel';
        // If the URL has no 'exp', cache with exp=now so it's treated as
        // already-expired and re-signed on the next resolve (cache disabled).
        final exp = int.tryParse(Uri.parse(url).queryParameters['exp'] ?? '') ?? now;
        _cache[id] = _Signed(url, exp);
        result[id] = url;
      });
    } on DioException {
      // Transport/HTTP error → leave unresolved ids out (caller falls back to TTS).
    } catch (_) {
      // Unexpected response shape → same graceful fallback.
    }
    return result;
  }
}

class _Signed {
  _Signed(this.url, this.exp);
  final String url;
  final int exp;
}
