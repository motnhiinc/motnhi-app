import 'package:freezed_annotation/freezed_annotation.dart';

part 'narration_segment.freezed.dart';
part 'narration_segment.g.dart';

/// One spoken segment of a page (§10 `narration_segments`, the persisted form
/// of the §9.4.2 narration-script JSON). Drives audio, sentence highlighting,
/// and tap-to-play-segment AR interactions from a single structured source.
@freezed
abstract class NarrationSegment with _$NarrationSegment {
  const NarrationSegment._();

  const factory NarrationSegment({
    required String id,
    required String storyId,
    required String pageId,

    /// `narrator` or a character key (§4.2 `speaker_key`).
    required String speakerKey,
    required String text,

    /// Licensed/platform-approved voice reference (§7.1.3). Never voice cloning.
    required String voiceId,
    String? emotion,

    /// Playback speed multiplier (`speed NUMERIC(4,2)` in §10).
    @Default(1.0) double speed,

    /// Rendered audio clip; served via signed URL in production (§9.5.4).
    /// Null in this slice falls back to DEV-ONLY on-device TTS.
    String? audioAssetId,

    /// Segment timing for gapless playback + highlight sync (§4.2).
    @Default(0) int startMs,
    @Default(0) int endMs,

    /// Playback order within the page (`sort_order NOT NULL`).
    required int sortOrder,
  }) = _NarrationSegment;

  factory NarrationSegment.fromJson(Map<String, dynamic> json) =>
      _$NarrationSegmentFromJson(json);

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);

  /// True when a real pre-generated clip exists (production path); false means
  /// the engine must use the DEV-ONLY TTS fallback.
  bool get hasAudioAsset => audioAssetId != null && audioAssetId!.isNotEmpty;
}
