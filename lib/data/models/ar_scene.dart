import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'ar_scene.freezed.dart';
part 'ar_scene.g.dart';

/// A 3D position offset for an AR asset relative to the detected target
/// (§9.3.3 `position`). Units are meters in AR space.
@freezed
abstract class ArVector3 with _$ArVector3 {
  const factory ArVector3({
    @Default(0.0) double x,
    @Default(0.0) double y,
    @Default(0.0) double z,
  }) = _ArVector3;

  factory ArVector3.fromJson(Map<String, dynamic> json) =>
      _$ArVector3FromJson(json);
}

/// A placeable asset within an AR scene (§9.3.3 `assets[]`, §3.7 2D-first).
@freezed
abstract class ArSceneAsset with _$ArSceneAsset {
  const factory ArSceneAsset({
    required String assetId,
    required ArAssetType type,
    @Default(ArVector3()) ArVector3 position,
    @Default(1.0) double scale,
    required String defaultAnimation,

    /// Local/CDN image used to render a 2D character/object overlay.
    String? imageAsset,
  }) = _ArSceneAsset;

  factory ArSceneAsset.fromJson(Map<String, dynamic> json) =>
      _$ArSceneAssetFromJson(json);
}

/// A bounded interaction on an AR asset (§9.3.3 `interactions[]`).
/// MVP supports tap → play a narration/audio segment.
@freezed
abstract class ArInteraction with _$ArInteraction {
  const factory ArInteraction({
    required ArTrigger trigger,
    required String targetAssetId,
    required ArAction action,

    /// Narration segment to play when [action] is `play_audio_segment`,
    /// linking a tap back to the audio engine (§4.2, §9.3.3).
    String? audioSegmentId,
  }) = _ArInteraction;

  factory ArInteraction.fromJson(Map<String, dynamic> json) =>
      _$ArInteractionFromJson(json);
}

/// The structured `scene_json` payload (§9.3.3) persisted in
/// `ar_scenes.scene_json` JSONB (§10).
@freezed
abstract class ArSceneData with _$ArSceneData {
  const factory ArSceneData({
    required String sceneId,
    @Default(ArAnchorType.imageTarget) ArAnchorType anchorType,
    @Default(<ArSceneAsset>[]) List<ArSceneAsset> assets,
    @Default(<ArInteraction>[]) List<ArInteraction> interactions,
  }) = _ArSceneData;

  factory ArSceneData.fromJson(Map<String, dynamic> json) =>
      _$ArSceneDataFromJson(json);
}

/// An AR scene row (§10 `ar_scenes`): bound to a page, carrying the typed
/// `scene_json` and its own publishing [status] so only published scenes ship
/// to devices (§3.5).
@freezed
abstract class ArScene with _$ArScene {
  const ArScene._();

  const factory ArScene({
    required String id,
    required String storyId,

    /// FK → `story_pages.id`; the join key from a recognized image target back
    /// to this scene (§3.6).
    required String pageId,
    required ArSceneData sceneJson,
    @Default(ContentStatus.published) ContentStatus status,
  }) = _ArScene;

  factory ArScene.fromJson(Map<String, dynamic> json) =>
      _$ArSceneFromJson(json);

  bool get isPublished => status == ContentStatus.published;
}
