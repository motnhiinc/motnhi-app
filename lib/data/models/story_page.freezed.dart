// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'story_page.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StoryPage {

 String get id; String get storyId; int get pageNumber; String? get pageText;/// Source illustration for the page; fed into the image-target pipeline
/// and shown in the player (§3.6 `page_image_asset_id`).
 String? get pageImageAssetId;/// Links the printed page to its AR reference-image target (§9.3.1, §11.5).
 String? get imageTargetId;
/// Create a copy of StoryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoryPageCopyWith<StoryPage> get copyWith => _$StoryPageCopyWithImpl<StoryPage>(this as StoryPage, _$identity);

  /// Serializes this StoryPage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoryPage&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageNumber, pageNumber) || other.pageNumber == pageNumber)&&(identical(other.pageText, pageText) || other.pageText == pageText)&&(identical(other.pageImageAssetId, pageImageAssetId) || other.pageImageAssetId == pageImageAssetId)&&(identical(other.imageTargetId, imageTargetId) || other.imageTargetId == imageTargetId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageNumber,pageText,pageImageAssetId,imageTargetId);

@override
String toString() {
  return 'StoryPage(id: $id, storyId: $storyId, pageNumber: $pageNumber, pageText: $pageText, pageImageAssetId: $pageImageAssetId, imageTargetId: $imageTargetId)';
}


}

/// @nodoc
abstract mixin class $StoryPageCopyWith<$Res>  {
  factory $StoryPageCopyWith(StoryPage value, $Res Function(StoryPage) _then) = _$StoryPageCopyWithImpl;
@useResult
$Res call({
 String id, String storyId, int pageNumber, String? pageText, String? pageImageAssetId, String? imageTargetId
});




}
/// @nodoc
class _$StoryPageCopyWithImpl<$Res>
    implements $StoryPageCopyWith<$Res> {
  _$StoryPageCopyWithImpl(this._self, this._then);

  final StoryPage _self;
  final $Res Function(StoryPage) _then;

/// Create a copy of StoryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? storyId = null,Object? pageNumber = null,Object? pageText = freezed,Object? pageImageAssetId = freezed,Object? imageTargetId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageNumber: null == pageNumber ? _self.pageNumber : pageNumber // ignore: cast_nullable_to_non_nullable
as int,pageText: freezed == pageText ? _self.pageText : pageText // ignore: cast_nullable_to_non_nullable
as String?,pageImageAssetId: freezed == pageImageAssetId ? _self.pageImageAssetId : pageImageAssetId // ignore: cast_nullable_to_non_nullable
as String?,imageTargetId: freezed == imageTargetId ? _self.imageTargetId : imageTargetId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StoryPage].
extension StoryPagePatterns on StoryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoryPage value)  $default,){
final _that = this;
switch (_that) {
case _StoryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoryPage value)?  $default,){
final _that = this;
switch (_that) {
case _StoryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String storyId,  int pageNumber,  String? pageText,  String? pageImageAssetId,  String? imageTargetId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoryPage() when $default != null:
return $default(_that.id,_that.storyId,_that.pageNumber,_that.pageText,_that.pageImageAssetId,_that.imageTargetId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String storyId,  int pageNumber,  String? pageText,  String? pageImageAssetId,  String? imageTargetId)  $default,) {final _that = this;
switch (_that) {
case _StoryPage():
return $default(_that.id,_that.storyId,_that.pageNumber,_that.pageText,_that.pageImageAssetId,_that.imageTargetId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String storyId,  int pageNumber,  String? pageText,  String? pageImageAssetId,  String? imageTargetId)?  $default,) {final _that = this;
switch (_that) {
case _StoryPage() when $default != null:
return $default(_that.id,_that.storyId,_that.pageNumber,_that.pageText,_that.pageImageAssetId,_that.imageTargetId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StoryPage extends StoryPage {
  const _StoryPage({required this.id, required this.storyId, required this.pageNumber, this.pageText, this.pageImageAssetId, this.imageTargetId}): super._();
  factory _StoryPage.fromJson(Map<String, dynamic> json) => _$StoryPageFromJson(json);

@override final  String id;
@override final  String storyId;
@override final  int pageNumber;
@override final  String? pageText;
/// Source illustration for the page; fed into the image-target pipeline
/// and shown in the player (§3.6 `page_image_asset_id`).
@override final  String? pageImageAssetId;
/// Links the printed page to its AR reference-image target (§9.3.1, §11.5).
@override final  String? imageTargetId;

/// Create a copy of StoryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoryPageCopyWith<_StoryPage> get copyWith => __$StoryPageCopyWithImpl<_StoryPage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoryPageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoryPage&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageNumber, pageNumber) || other.pageNumber == pageNumber)&&(identical(other.pageText, pageText) || other.pageText == pageText)&&(identical(other.pageImageAssetId, pageImageAssetId) || other.pageImageAssetId == pageImageAssetId)&&(identical(other.imageTargetId, imageTargetId) || other.imageTargetId == imageTargetId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageNumber,pageText,pageImageAssetId,imageTargetId);

@override
String toString() {
  return 'StoryPage(id: $id, storyId: $storyId, pageNumber: $pageNumber, pageText: $pageText, pageImageAssetId: $pageImageAssetId, imageTargetId: $imageTargetId)';
}


}

/// @nodoc
abstract mixin class _$StoryPageCopyWith<$Res> implements $StoryPageCopyWith<$Res> {
  factory _$StoryPageCopyWith(_StoryPage value, $Res Function(_StoryPage) _then) = __$StoryPageCopyWithImpl;
@override @useResult
$Res call({
 String id, String storyId, int pageNumber, String? pageText, String? pageImageAssetId, String? imageTargetId
});




}
/// @nodoc
class __$StoryPageCopyWithImpl<$Res>
    implements _$StoryPageCopyWith<$Res> {
  __$StoryPageCopyWithImpl(this._self, this._then);

  final _StoryPage _self;
  final $Res Function(_StoryPage) _then;

/// Create a copy of StoryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? storyId = null,Object? pageNumber = null,Object? pageText = freezed,Object? pageImageAssetId = freezed,Object? imageTargetId = freezed,}) {
  return _then(_StoryPage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageNumber: null == pageNumber ? _self.pageNumber : pageNumber // ignore: cast_nullable_to_non_nullable
as int,pageText: freezed == pageText ? _self.pageText : pageText // ignore: cast_nullable_to_non_nullable
as String?,pageImageAssetId: freezed == pageImageAssetId ? _self.pageImageAssetId : pageImageAssetId // ignore: cast_nullable_to_non_nullable
as String?,imageTargetId: freezed == imageTargetId ? _self.imageTargetId : imageTargetId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
