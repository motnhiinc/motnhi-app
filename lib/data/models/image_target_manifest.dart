import 'package:freezed_annotation/freezed_annotation.dart';

part 'image_target_manifest.freezed.dart';
part 'image_target_manifest.g.dart';

/// A single scannable page target inside a story's image-target manifest
/// (§4.2 `ImageTargetEntry`). `referenceImageUrl` is null until a page-image
/// binary is registered and signable (§4.3); the field shape is correct for
/// when image assets land later.
@freezed
abstract class ImageTarget with _$ImageTarget {
  const factory ImageTarget({
    required String pageId,
    required int pageNumber,
    required String imageTargetId,
    String? referenceImageUrl,
    required int physicalWidthMm,
  }) = _ImageTarget;

  factory ImageTarget.fromJson(Map<String, dynamic> json) =>
      _$ImageTargetFromJson(json);
}

/// The per-story image-target manifest (§4.2 `ImageTargetManifest`).
/// `version` is a constant `1` for MVP, documented as the future
/// cache-invalidation hook (§11.5). A story with no targeted pages returns an
/// empty `targets` list (valid, not an error — §4.1).
@freezed
abstract class ImageTargetManifest with _$ImageTargetManifest {
  const factory ImageTargetManifest({
    required String storyId,
    required int version,
    @Default(<ImageTarget>[]) List<ImageTarget> targets,
  }) = _ImageTargetManifest;

  factory ImageTargetManifest.fromJson(Map<String, dynamic> json) =>
      _$ImageTargetManifestFromJson(json);
}
