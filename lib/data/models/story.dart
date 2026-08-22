import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'story.freezed.dart';
part 'story.g.dart';

/// A story in the curated library (§10 `stories` + the §11.1 library DTO).
/// Content-catalog entity, independent of any child/user.
@freezed
abstract class Story with _$Story {
  const Story._();

  const factory Story({
    required String id,
    required String title,
    required String slug,
    String? description,

    /// Age range (§10 `age_min`/`age_max`).
    @Default(3) int ageMin,
    @Default(8) int ageMax,
    @Default('en') String languageCode,
    @Default(0) int durationSeconds,

    /// Library cover image (bundled asset path in this slice; CDN URL later).
    String? coverAssetId,
    @Default(ContentStatus.published) ContentStatus contentStatus,
    String? rightsOwnerId,

    /// Theme tags for browsing (§7.1.1).
    @Default(<StoryTheme>[]) List<StoryTheme> themes,

    /// Client/runtime flags (§11.1). Local impl unlocks all demo content;
    /// premium/publisher-code stories stay locked until entitled (§5.7).
    @Default(false) bool isDownloaded,
    @Default(true) bool isUnlocked,

    /// True when this story was captured in-app by the user rather than
    /// curated (server-side `owner_user_id IS NOT NULL`). Gates the per-read
    /// narration fetcher in the player.
    @Default(false) bool isAuthored,
  }) = _Story;

  factory Story.fromJson(Map<String, dynamic> json) => _$StoryFromJson(json);

  /// Whether this story is appropriate for [band] (used by library filters).
  bool matchesAgeBand(AgeBand band) =>
      ageMin <= band.max && ageMax >= band.min;

  String get ageRangeLabel => '$ageMin–$ageMax';

  Duration get duration => Duration(seconds: durationSeconds);
}
