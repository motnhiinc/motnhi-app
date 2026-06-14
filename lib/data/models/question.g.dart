// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'question.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AnswerChoice _$AnswerChoiceFromJson(Map<String, dynamic> json) =>
    _AnswerChoice(
      id: json['id'] as String,
      label: json['label'] as String,
      imageAsset: json['image_asset'] as String?,
      emoji: json['emoji'] as String?,
      isCorrect: json['is_correct'] as bool? ?? false,
    );

Map<String, dynamic> _$AnswerChoiceToJson(_AnswerChoice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'image_asset': instance.imageAsset,
      'emoji': instance.emoji,
      'is_correct': instance.isCorrect,
    };

_Question _$QuestionFromJson(Map<String, dynamic> json) => _Question(
  id: json['id'] as String,
  pageId: json['page_id'] as String,
  type: $enumDecode(_$QuestionTypeEnumMap, json['type']),
  prompt: json['prompt'] as String,
  choices:
      (json['choices'] as List<dynamic>?)
          ?.map((e) => AnswerChoice.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <AnswerChoice>[],
);

Map<String, dynamic> _$QuestionToJson(_Question instance) => <String, dynamic>{
  'id': instance.id,
  'page_id': instance.pageId,
  'type': _$QuestionTypeEnumMap[instance.type]!,
  'prompt': instance.prompt,
  'choices': instance.choices.map((e) => e.toJson()).toList(),
};

const _$QuestionTypeEnumMap = {
  QuestionType.multipleChoiceImage: 'multiple_choice_image',
  QuestionType.tapTheObject: 'tap_the_object',
  QuestionType.chooseTheEmotion: 'choose_the_emotion',
  QuestionType.whatHappensNext: 'what_happens_next',
};
