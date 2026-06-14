import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'question.freezed.dart';
part 'question.g.dart';

/// One bounded answer choice (§7.1.5). Image-led so pre-readers can answer.
@freezed
abstract class AnswerChoice with _$AnswerChoice {
  const factory AnswerChoice({
    required String id,
    required String label,

    /// Optional picture for the choice (multiple-choice-with-images).
    String? imageAsset,

    /// Optional emoji glyph used when no image asset is bundled.
    String? emoji,
    @Default(false) bool isCorrect,
  }) = _AnswerChoice;

  factory AnswerChoice.fromJson(Map<String, dynamic> json) =>
      _$AnswerChoiceFromJson(json);
}

/// A guided comprehension question (§7.1.5). Not a spec DB table, but required
/// by the child experience; carried with story content. Bounded tap choices
/// only — never a free-form chatbot (§8.4, §13.1).
@freezed
abstract class Question with _$Question {
  const Question._();

  const factory Question({
    required String id,

    /// Page this question relates to (for sequencing after the page is read).
    required String pageId,
    required QuestionType type,
    required String prompt,
    @Default(<AnswerChoice>[]) List<AnswerChoice> choices,
  }) = _Question;

  factory Question.fromJson(Map<String, dynamic> json) =>
      _$QuestionFromJson(json);

  AnswerChoice? get correctChoice =>
      choices.where((c) => c.isCorrect).firstOrNull;
}
