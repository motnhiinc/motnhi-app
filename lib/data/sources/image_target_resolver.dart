import 'package:dio/dio.dart';

import '../models/image_target_manifest.dart';
import 'api_client.dart';

/// Fetches a story's image-target manifest via
/// `GET /v1/stories/{story_id}/image-target-manifest` (spec §4.1, §5.1). The
/// parsed manifest is cached by `storyId`; on a transport/parse error a cached
/// manifest (if any) is returned so the scan flow degrades gracefully (§7).
abstract class ImageTargetResolver {
  Future<ImageTargetManifest> fetch(String storyId);
}

class HttpImageTargetResolver implements ImageTargetResolver {
  HttpImageTargetResolver(this._api);

  final ApiClient _api;
  final Map<String, ImageTargetManifest> _cache = {};

  @override
  Future<ImageTargetManifest> fetch(String storyId) async {
    final cached = _cache[storyId];
    if (cached != null) return cached;

    try {
      final resp = await _api.send(
        () => _api.dio.get('/v1/stories/$storyId/image-target-manifest'),
      );
      final manifest =
          ImageTargetManifest.fromJson(resp.data as Map<String, dynamic>);
      _cache[storyId] = manifest;
      return manifest;
    } on DioException {
      // Transport/HTTP error → fall back to a cached manifest if present.
      final fallback = _cache[storyId];
      if (fallback != null) return fallback;
      rethrow;
    } catch (_) {
      // Unexpected response shape → same graceful fallback.
      final fallback = _cache[storyId];
      if (fallback != null) return fallback;
      rethrow;
    }
  }
}
