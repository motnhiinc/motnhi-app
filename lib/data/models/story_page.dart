import 'package:freezed_annotation/freezed_annotation.dart';

part 'story_page.freezed.dart';
part 'story_page.g.dart';

/// A single page of a story (§10 `story_pages`).
@freezed
abstract class StoryPage with _$StoryPage {
  const StoryPage._();

  const factory StoryPage({
    required String id,
    required String storyId,
    required int pageNumber,
    String? pageText,

    /// Source illustration for the page; fed into the image-target pipeline
    /// and shown in the player (§3.6 `page_image_asset_id`).
    String? pageImageAssetId,

    /// Links the printed page to its AR reference-image target (§9.3.1, §11.5).
    String? imageTargetId,
  }) = _StoryPage;

  factory StoryPage.fromJson(Map<String, dynamic> json) =>
      _$StoryPageFromJson(json);

  bool get hasImageTarget =>
      imageTargetId != null && imageTargetId!.isNotEmpty;
}
