// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'question.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AnswerChoice {

 String get id; String get label;/// Optional picture for the choice (multiple-choice-with-images).
 String? get imageAsset;/// Optional emoji glyph used when no image asset is bundled.
 String? get emoji; bool get isCorrect;
/// Create a copy of AnswerChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerChoiceCopyWith<AnswerChoice> get copyWith => _$AnswerChoiceCopyWithImpl<AnswerChoice>(this as AnswerChoice, _$identity);

  /// Serializes this AnswerChoice to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerChoice&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.imageAsset, imageAsset) || other.imageAsset == imageAsset)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.isCorrect, isCorrect) || other.isCorrect == isCorrect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,imageAsset,emoji,isCorrect);

@override
String toString() {
  return 'AnswerChoice(id: $id, label: $label, imageAsset: $imageAsset, emoji: $emoji, isCorrect: $isCorrect)';
}


}

/// @nodoc
abstract mixin class $AnswerChoiceCopyWith<$Res>  {
  factory $AnswerChoiceCopyWith(AnswerChoice value, $Res Function(AnswerChoice) _then) = _$AnswerChoiceCopyWithImpl;
@useResult
$Res call({
 String id, String label, String? imageAsset, String? emoji, bool isCorrect
});




}
/// @nodoc
class _$AnswerChoiceCopyWithImpl<$Res>
    implements $AnswerChoiceCopyWith<$Res> {
  _$AnswerChoiceCopyWithImpl(this._self, this._then);

  final AnswerChoice _self;
  final $Res Function(AnswerChoice) _then;

/// Create a copy of AnswerChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? imageAsset = freezed,Object? emoji = freezed,Object? isCorrect = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,imageAsset: freezed == imageAsset ? _self.imageAsset : imageAsset // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,isCorrect: null == isCorrect ? _self.isCorrect : isCorrect // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AnswerChoice].
extension AnswerChoicePatterns on AnswerChoice {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnswerChoice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnswerChoice() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnswerChoice value)  $default,){
final _that = this;
switch (_that) {
case _AnswerChoice():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnswerChoice value)?  $default,){
final _that = this;
switch (_that) {
case _AnswerChoice() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String? imageAsset,  String? emoji,  bool isCorrect)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnswerChoice() when $default != null:
return $default(_that.id,_that.label,_that.imageAsset,_that.emoji,_that.isCorrect);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String? imageAsset,  String? emoji,  bool isCorrect)  $default,) {final _that = this;
switch (_that) {
case _AnswerChoice():
return $default(_that.id,_that.label,_that.imageAsset,_that.emoji,_that.isCorrect);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String? imageAsset,  String? emoji,  bool isCorrect)?  $default,) {final _that = this;
switch (_that) {
case _AnswerChoice() when $default != null:
return $default(_that.id,_that.label,_that.imageAsset,_that.emoji,_that.isCorrect);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AnswerChoice implements AnswerChoice {
  const _AnswerChoice({required this.id, required this.label, this.imageAsset, this.emoji, this.isCorrect = false});
  factory _AnswerChoice.fromJson(Map<String, dynamic> json) => _$AnswerChoiceFromJson(json);

@override final  String id;
@override final  String label;
/// Optional picture for the choice (multiple-choice-with-images).
@override final  String? imageAsset;
/// Optional emoji glyph used when no image asset is bundled.
@override final  String? emoji;
@override@JsonKey() final  bool isCorrect;

/// Create a copy of AnswerChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnswerChoiceCopyWith<_AnswerChoice> get copyWith => __$AnswerChoiceCopyWithImpl<_AnswerChoice>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AnswerChoiceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnswerChoice&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.imageAsset, imageAsset) || other.imageAsset == imageAsset)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.isCorrect, isCorrect) || other.isCorrect == isCorrect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,label,imageAsset,emoji,isCorrect);

@override
String toString() {
  return 'AnswerChoice(id: $id, label: $label, imageAsset: $imageAsset, emoji: $emoji, isCorrect: $isCorrect)';
}


}

/// @nodoc
abstract mixin class _$AnswerChoiceCopyWith<$Res> implements $AnswerChoiceCopyWith<$Res> {
  factory _$AnswerChoiceCopyWith(_AnswerChoice value, $Res Function(_AnswerChoice) _then) = __$AnswerChoiceCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String? imageAsset, String? emoji, bool isCorrect
});




}
/// @nodoc
class __$AnswerChoiceCopyWithImpl<$Res>
    implements _$AnswerChoiceCopyWith<$Res> {
  __$AnswerChoiceCopyWithImpl(this._self, this._then);

  final _AnswerChoice _self;
  final $Res Function(_AnswerChoice) _then;

/// Create a copy of AnswerChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? imageAsset = freezed,Object? emoji = freezed,Object? isCorrect = null,}) {
  return _then(_AnswerChoice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,imageAsset: freezed == imageAsset ? _self.imageAsset : imageAsset // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,isCorrect: null == isCorrect ? _self.isCorrect : isCorrect // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$Question {

 String get id;/// Page this question relates to (for sequencing after the page is read).
 String get pageId; QuestionType get type; String get prompt; List<AnswerChoice> get choices;
/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionCopyWith<Question> get copyWith => _$QuestionCopyWithImpl<Question>(this as Question, _$identity);

  /// Serializes this Question to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Question&&(identical(other.id, id) || other.id == id)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.type, type) || other.type == type)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&const DeepCollectionEquality().equals(other.choices, choices));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,pageId,type,prompt,const DeepCollectionEquality().hash(choices));

@override
String toString() {
  return 'Question(id: $id, pageId: $pageId, type: $type, prompt: $prompt, choices: $choices)';
}


}

/// @nodoc
abstract mixin class $QuestionCopyWith<$Res>  {
  factory $QuestionCopyWith(Question value, $Res Function(Question) _then) = _$QuestionCopyWithImpl;
@useResult
$Res call({
 String id, String pageId, QuestionType type, String prompt, List<AnswerChoice> choices
});




}
/// @nodoc
class _$QuestionCopyWithImpl<$Res>
    implements $QuestionCopyWith<$Res> {
  _$QuestionCopyWithImpl(this._self, this._then);

  final Question _self;
  final $Res Function(Question) _then;

/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? pageId = null,Object? type = null,Object? prompt = null,Object? choices = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as List<AnswerChoice>,
  ));
}

}


/// Adds pattern-matching-related methods to [Question].
extension QuestionPatterns on Question {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Question value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Question value)  $default,){
final _that = this;
switch (_that) {
case _Question():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Question value)?  $default,){
final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String pageId,  QuestionType type,  String prompt,  List<AnswerChoice> choices)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that.id,_that.pageId,_that.type,_that.prompt,_that.choices);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String pageId,  QuestionType type,  String prompt,  List<AnswerChoice> choices)  $default,) {final _that = this;
switch (_that) {
case _Question():
return $default(_that.id,_that.pageId,_that.type,_that.prompt,_that.choices);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String pageId,  QuestionType type,  String prompt,  List<AnswerChoice> choices)?  $default,) {final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that.id,_that.pageId,_that.type,_that.prompt,_that.choices);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Question extends Question {
  const _Question({required this.id, required this.pageId, required this.type, required this.prompt, final  List<AnswerChoice> choices = const <AnswerChoice>[]}): _choices = choices,super._();
  factory _Question.fromJson(Map<String, dynamic> json) => _$QuestionFromJson(json);

@override final  String id;
/// Page this question relates to (for sequencing after the page is read).
@override final  String pageId;
@override final  QuestionType type;
@override final  String prompt;
 final  List<AnswerChoice> _choices;
@override@JsonKey() List<AnswerChoice> get choices {
  if (_choices is EqualUnmodifiableListView) return _choices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_choices);
}


/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionCopyWith<_Question> get copyWith => __$QuestionCopyWithImpl<_Question>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuestionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Question&&(identical(other.id, id) || other.id == id)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.type, type) || other.type == type)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&const DeepCollectionEquality().equals(other._choices, _choices));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,pageId,type,prompt,const DeepCollectionEquality().hash(_choices));

@override
String toString() {
  return 'Question(id: $id, pageId: $pageId, type: $type, prompt: $prompt, choices: $choices)';
}


}

/// @nodoc
abstract mixin class _$QuestionCopyWith<$Res> implements $QuestionCopyWith<$Res> {
  factory _$QuestionCopyWith(_Question value, $Res Function(_Question) _then) = __$QuestionCopyWithImpl;
@override @useResult
$Res call({
 String id, String pageId, QuestionType type, String prompt, List<AnswerChoice> choices
});




}
/// @nodoc
class __$QuestionCopyWithImpl<$Res>
    implements _$QuestionCopyWith<$Res> {
  __$QuestionCopyWithImpl(this._self, this._then);

  final _Question _self;
  final $Res Function(_Question) _then;

/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? pageId = null,Object? type = null,Object? prompt = null,Object? choices = null,}) {
  return _then(_Question(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,choices: null == choices ? _self._choices : choices // ignore: cast_nullable_to_non_nullable
as List<AnswerChoice>,
  ));
}


}

// dart format on
