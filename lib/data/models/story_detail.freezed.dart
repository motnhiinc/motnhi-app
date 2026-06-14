// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'story_detail.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StoryDetail {

 Story get story; List<StoryPage> get pages; List<NarrationSegment> get segments; List<ArScene> get arScenes; List<Question> get questions;
/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoryDetailCopyWith<StoryDetail> get copyWith => _$StoryDetailCopyWithImpl<StoryDetail>(this as StoryDetail, _$identity);

  /// Serializes this StoryDetail to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoryDetail&&(identical(other.story, story) || other.story == story)&&const DeepCollectionEquality().equals(other.pages, pages)&&const DeepCollectionEquality().equals(other.segments, segments)&&const DeepCollectionEquality().equals(other.arScenes, arScenes)&&const DeepCollectionEquality().equals(other.questions, questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,story,const DeepCollectionEquality().hash(pages),const DeepCollectionEquality().hash(segments),const DeepCollectionEquality().hash(arScenes),const DeepCollectionEquality().hash(questions));

@override
String toString() {
  return 'StoryDetail(story: $story, pages: $pages, segments: $segments, arScenes: $arScenes, questions: $questions)';
}


}

/// @nodoc
abstract mixin class $StoryDetailCopyWith<$Res>  {
  factory $StoryDetailCopyWith(StoryDetail value, $Res Function(StoryDetail) _then) = _$StoryDetailCopyWithImpl;
@useResult
$Res call({
 Story story, List<StoryPage> pages, List<NarrationSegment> segments, List<ArScene> arScenes, List<Question> questions
});


$StoryCopyWith<$Res> get story;

}
/// @nodoc
class _$StoryDetailCopyWithImpl<$Res>
    implements $StoryDetailCopyWith<$Res> {
  _$StoryDetailCopyWithImpl(this._self, this._then);

  final StoryDetail _self;
  final $Res Function(StoryDetail) _then;

/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? story = null,Object? pages = null,Object? segments = null,Object? arScenes = null,Object? questions = null,}) {
  return _then(_self.copyWith(
story: null == story ? _self.story : story // ignore: cast_nullable_to_non_nullable
as Story,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as List<StoryPage>,segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<NarrationSegment>,arScenes: null == arScenes ? _self.arScenes : arScenes // ignore: cast_nullable_to_non_nullable
as List<ArScene>,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<Question>,
  ));
}
/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StoryCopyWith<$Res> get story {
  
  return $StoryCopyWith<$Res>(_self.story, (value) {
    return _then(_self.copyWith(story: value));
  });
}
}


/// Adds pattern-matching-related methods to [StoryDetail].
extension StoryDetailPatterns on StoryDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoryDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoryDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoryDetail value)  $default,){
final _that = this;
switch (_that) {
case _StoryDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoryDetail value)?  $default,){
final _that = this;
switch (_that) {
case _StoryDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Story story,  List<StoryPage> pages,  List<NarrationSegment> segments,  List<ArScene> arScenes,  List<Question> questions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoryDetail() when $default != null:
return $default(_that.story,_that.pages,_that.segments,_that.arScenes,_that.questions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Story story,  List<StoryPage> pages,  List<NarrationSegment> segments,  List<ArScene> arScenes,  List<Question> questions)  $default,) {final _that = this;
switch (_that) {
case _StoryDetail():
return $default(_that.story,_that.pages,_that.segments,_that.arScenes,_that.questions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Story story,  List<StoryPage> pages,  List<NarrationSegment> segments,  List<ArScene> arScenes,  List<Question> questions)?  $default,) {final _that = this;
switch (_that) {
case _StoryDetail() when $default != null:
return $default(_that.story,_that.pages,_that.segments,_that.arScenes,_that.questions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StoryDetail extends StoryDetail {
  const _StoryDetail({required this.story, final  List<StoryPage> pages = const <StoryPage>[], final  List<NarrationSegment> segments = const <NarrationSegment>[], final  List<ArScene> arScenes = const <ArScene>[], final  List<Question> questions = const <Question>[]}): _pages = pages,_segments = segments,_arScenes = arScenes,_questions = questions,super._();
  factory _StoryDetail.fromJson(Map<String, dynamic> json) => _$StoryDetailFromJson(json);

@override final  Story story;
 final  List<StoryPage> _pages;
@override@JsonKey() List<StoryPage> get pages {
  if (_pages is EqualUnmodifiableListView) return _pages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pages);
}

 final  List<NarrationSegment> _segments;
@override@JsonKey() List<NarrationSegment> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}

 final  List<ArScene> _arScenes;
@override@JsonKey() List<ArScene> get arScenes {
  if (_arScenes is EqualUnmodifiableListView) return _arScenes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_arScenes);
}

 final  List<Question> _questions;
@override@JsonKey() List<Question> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}


/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoryDetailCopyWith<_StoryDetail> get copyWith => __$StoryDetailCopyWithImpl<_StoryDetail>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoryDetailToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoryDetail&&(identical(other.story, story) || other.story == story)&&const DeepCollectionEquality().equals(other._pages, _pages)&&const DeepCollectionEquality().equals(other._segments, _segments)&&const DeepCollectionEquality().equals(other._arScenes, _arScenes)&&const DeepCollectionEquality().equals(other._questions, _questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,story,const DeepCollectionEquality().hash(_pages),const DeepCollectionEquality().hash(_segments),const DeepCollectionEquality().hash(_arScenes),const DeepCollectionEquality().hash(_questions));

@override
String toString() {
  return 'StoryDetail(story: $story, pages: $pages, segments: $segments, arScenes: $arScenes, questions: $questions)';
}


}

/// @nodoc
abstract mixin class _$StoryDetailCopyWith<$Res> implements $StoryDetailCopyWith<$Res> {
  factory _$StoryDetailCopyWith(_StoryDetail value, $Res Function(_StoryDetail) _then) = __$StoryDetailCopyWithImpl;
@override @useResult
$Res call({
 Story story, List<StoryPage> pages, List<NarrationSegment> segments, List<ArScene> arScenes, List<Question> questions
});


@override $StoryCopyWith<$Res> get story;

}
/// @nodoc
class __$StoryDetailCopyWithImpl<$Res>
    implements _$StoryDetailCopyWith<$Res> {
  __$StoryDetailCopyWithImpl(this._self, this._then);

  final _StoryDetail _self;
  final $Res Function(_StoryDetail) _then;

/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? story = null,Object? pages = null,Object? segments = null,Object? arScenes = null,Object? questions = null,}) {
  return _then(_StoryDetail(
story: null == story ? _self.story : story // ignore: cast_nullable_to_non_nullable
as Story,pages: null == pages ? _self._pages : pages // ignore: cast_nullable_to_non_nullable
as List<StoryPage>,segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<NarrationSegment>,arScenes: null == arScenes ? _self._arScenes : arScenes // ignore: cast_nullable_to_non_nullable
as List<ArScene>,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<Question>,
  ));
}

/// Create a copy of StoryDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StoryCopyWith<$Res> get story {
  
  return $StoryCopyWith<$Res>(_self.story, (value) {
    return _then(_self.copyWith(story: value));
  });
}
}

// dart format on
