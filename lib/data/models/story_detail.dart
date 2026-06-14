import 'package:freezed_annotation/freezed_annotation.dart';

import 'ar_scene.dart';
import 'narration_segment.dart';
import 'question.dart';
import 'story.dart';
import 'story_page.dart';

part 'story_detail.freezed.dart';
part 'story_detail.g.dart';

/// Full story payload returned by `GET /v1/stories/{id}` (§11.2): metadata,
/// pages, narration, AR scenes, the asset manifest, and the bounded questions.
@freezed
abstract class StoryDetail with _$StoryDetail {
  const StoryDetail._();

  const factory StoryDetail({
    required Story story,
    @Default(<StoryPage>[]) List<StoryPage> pages,
    @Default(<NarrationSegment>[]) List<NarrationSegment> segments,
    @Default(<ArScene>[]) List<ArScene> arScenes,
    @Default(<Question>[]) List<Question> questions,
  }) = _StoryDetail;

  factory StoryDetail.fromJson(Map<String, dynamic> json) =>
      _$StoryDetailFromJson(json);

  /// Pages in reading order.
  List<StoryPage> get orderedPages =>
      [...pages]..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

  /// Narration segments for [pageId] in playback order (§4.2 `sort_order`).
  List<NarrationSegment> segmentsForPage(String pageId) =>
      segments.where((s) => s.pageId == pageId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The published AR scene bound to [pageId], if any (§3.5).
  ArScene? arSceneForPage(String pageId) => arScenes
      .where((s) => s.pageId == pageId && s.isPublished)
      .firstOrNull;

  /// Questions bound to [pageId].
  List<Question> questionsForPage(String pageId) =>
      questions.where((q) => q.pageId == pageId).toList();
}
