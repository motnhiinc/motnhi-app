import 'package:json_annotation/json_annotation.dart';

/// Child age band (§10 `child_profiles.age_band` CHECK, §7.1.1).
/// Band, never an exact birthdate — data minimization (§14.3).
enum AgeBand {
  @JsonValue('3-4')
  threeToFour('3-4', 3, 4),
  @JsonValue('5-6')
  fiveToSix('5-6', 5, 6),
  @JsonValue('7-8')
  sevenToEight('7-8', 7, 8);

  const AgeBand(this.label, this.min, this.max);

  final String label;
  final int min;
  final int max;
}

/// Publishing lifecycle persisted in the DB (§10 `content_status` /
/// `ar_scenes.status`). The four-value enum is the persisted approximation of
/// the six-state operational machine (§19.2); see SYSTEM_ARCHITECTURE §5.2.
enum ContentStatus {
  @JsonValue('draft')
  draft,
  @JsonValue('review')
  review,
  @JsonValue('published')
  published,
  @JsonValue('archived')
  archived,
}

/// How a story session was started (§10 `story_sessions.mode`).
enum SessionMode {
  @JsonValue('library')
  library,
  @JsonValue('scan')
  scan,
  @JsonValue('bedtime')
  bedtime,
  @JsonValue('classroom')
  classroom,
}

/// AR anchor type (§9.3.3 `anchor_type`). MVP is image-target only (§3.3).
enum ArAnchorType {
  @JsonValue('image_target')
  imageTarget,
  @JsonValue('plane')
  plane,
}

/// AR asset kind (§9.3.3 / §3.7). 2D-first for MVP.
enum ArAssetType {
  @JsonValue('2d_character')
  character2d,
  @JsonValue('2d_object')
  object2d,
  @JsonValue('3d_character')
  character3d,
}

/// AR interaction trigger (§9.3.3 `trigger`).
enum ArTrigger {
  @JsonValue('tap')
  tap,
  @JsonValue('auto')
  auto,
}

/// AR interaction action (§9.3.3 `action`).
enum ArAction {
  @JsonValue('play_audio_segment')
  playAudioSegment,
  @JsonValue('play_animation')
  playAnimation,
}

/// Interactive question type (§7.1.5). Bounded, tap-based — never free-form chat.
enum QuestionType {
  @JsonValue('multiple_choice_image')
  multipleChoiceImage,
  @JsonValue('tap_the_object')
  tapTheObject,
  @JsonValue('choose_the_emotion')
  chooseTheEmotion,
  @JsonValue('what_happens_next')
  whatHappensNext,
}

/// Story theme for library browsing (§7.1.1).
enum StoryTheme {
  @JsonValue('animals')
  animals,
  @JsonValue('bedtime')
  bedtime,
  @JsonValue('friendship')
  friendship,
  @JsonValue('emotions')
  emotions,
  @JsonValue('language_learning')
  languageLearning;

  String get label => switch (this) {
        StoryTheme.animals => 'Animals',
        StoryTheme.bedtime => 'Bedtime',
        StoryTheme.friendship => 'Friendship',
        StoryTheme.emotions => 'Emotions',
        StoryTheme.languageLearning => 'Language',
      };
}
