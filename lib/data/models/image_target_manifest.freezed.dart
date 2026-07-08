// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'image_target_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ImageTarget {

 String get pageId; int get pageNumber; String get imageTargetId; String? get referenceImageUrl; int get physicalWidthMm;
/// Create a copy of ImageTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageTargetCopyWith<ImageTarget> get copyWith => _$ImageTargetCopyWithImpl<ImageTarget>(this as ImageTarget, _$identity);

  /// Serializes this ImageTarget to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageTarget&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.pageNumber, pageNumber) || other.pageNumber == pageNumber)&&(identical(other.imageTargetId, imageTargetId) || other.imageTargetId == imageTargetId)&&(identical(other.referenceImageUrl, referenceImageUrl) || other.referenceImageUrl == referenceImageUrl)&&(identical(other.physicalWidthMm, physicalWidthMm) || other.physicalWidthMm == physicalWidthMm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,pageId,pageNumber,imageTargetId,referenceImageUrl,physicalWidthMm);

@override
String toString() {
  return 'ImageTarget(pageId: $pageId, pageNumber: $pageNumber, imageTargetId: $imageTargetId, referenceImageUrl: $referenceImageUrl, physicalWidthMm: $physicalWidthMm)';
}


}

/// @nodoc
abstract mixin class $ImageTargetCopyWith<$Res>  {
  factory $ImageTargetCopyWith(ImageTarget value, $Res Function(ImageTarget) _then) = _$ImageTargetCopyWithImpl;
@useResult
$Res call({
 String pageId, int pageNumber, String imageTargetId, String? referenceImageUrl, int physicalWidthMm
});




}
/// @nodoc
class _$ImageTargetCopyWithImpl<$Res>
    implements $ImageTargetCopyWith<$Res> {
  _$ImageTargetCopyWithImpl(this._self, this._then);

  final ImageTarget _self;
  final $Res Function(ImageTarget) _then;

/// Create a copy of ImageTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pageId = null,Object? pageNumber = null,Object? imageTargetId = null,Object? referenceImageUrl = freezed,Object? physicalWidthMm = null,}) {
  return _then(_self.copyWith(
pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,pageNumber: null == pageNumber ? _self.pageNumber : pageNumber // ignore: cast_nullable_to_non_nullable
as int,imageTargetId: null == imageTargetId ? _self.imageTargetId : imageTargetId // ignore: cast_nullable_to_non_nullable
as String,referenceImageUrl: freezed == referenceImageUrl ? _self.referenceImageUrl : referenceImageUrl // ignore: cast_nullable_to_non_nullable
as String?,physicalWidthMm: null == physicalWidthMm ? _self.physicalWidthMm : physicalWidthMm // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ImageTarget].
extension ImageTargetPatterns on ImageTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ImageTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ImageTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ImageTarget value)  $default,){
final _that = this;
switch (_that) {
case _ImageTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ImageTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ImageTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String pageId,  int pageNumber,  String imageTargetId,  String? referenceImageUrl,  int physicalWidthMm)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ImageTarget() when $default != null:
return $default(_that.pageId,_that.pageNumber,_that.imageTargetId,_that.referenceImageUrl,_that.physicalWidthMm);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String pageId,  int pageNumber,  String imageTargetId,  String? referenceImageUrl,  int physicalWidthMm)  $default,) {final _that = this;
switch (_that) {
case _ImageTarget():
return $default(_that.pageId,_that.pageNumber,_that.imageTargetId,_that.referenceImageUrl,_that.physicalWidthMm);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String pageId,  int pageNumber,  String imageTargetId,  String? referenceImageUrl,  int physicalWidthMm)?  $default,) {final _that = this;
switch (_that) {
case _ImageTarget() when $default != null:
return $default(_that.pageId,_that.pageNumber,_that.imageTargetId,_that.referenceImageUrl,_that.physicalWidthMm);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ImageTarget implements ImageTarget {
  const _ImageTarget({required this.pageId, required this.pageNumber, required this.imageTargetId, this.referenceImageUrl, required this.physicalWidthMm});
  factory _ImageTarget.fromJson(Map<String, dynamic> json) => _$ImageTargetFromJson(json);

@override final  String pageId;
@override final  int pageNumber;
@override final  String imageTargetId;
@override final  String? referenceImageUrl;
@override final  int physicalWidthMm;

/// Create a copy of ImageTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ImageTargetCopyWith<_ImageTarget> get copyWith => __$ImageTargetCopyWithImpl<_ImageTarget>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ImageTargetToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ImageTarget&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.pageNumber, pageNumber) || other.pageNumber == pageNumber)&&(identical(other.imageTargetId, imageTargetId) || other.imageTargetId == imageTargetId)&&(identical(other.referenceImageUrl, referenceImageUrl) || other.referenceImageUrl == referenceImageUrl)&&(identical(other.physicalWidthMm, physicalWidthMm) || other.physicalWidthMm == physicalWidthMm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,pageId,pageNumber,imageTargetId,referenceImageUrl,physicalWidthMm);

@override
String toString() {
  return 'ImageTarget(pageId: $pageId, pageNumber: $pageNumber, imageTargetId: $imageTargetId, referenceImageUrl: $referenceImageUrl, physicalWidthMm: $physicalWidthMm)';
}


}

/// @nodoc
abstract mixin class _$ImageTargetCopyWith<$Res> implements $ImageTargetCopyWith<$Res> {
  factory _$ImageTargetCopyWith(_ImageTarget value, $Res Function(_ImageTarget) _then) = __$ImageTargetCopyWithImpl;
@override @useResult
$Res call({
 String pageId, int pageNumber, String imageTargetId, String? referenceImageUrl, int physicalWidthMm
});




}
/// @nodoc
class __$ImageTargetCopyWithImpl<$Res>
    implements _$ImageTargetCopyWith<$Res> {
  __$ImageTargetCopyWithImpl(this._self, this._then);

  final _ImageTarget _self;
  final $Res Function(_ImageTarget) _then;

/// Create a copy of ImageTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pageId = null,Object? pageNumber = null,Object? imageTargetId = null,Object? referenceImageUrl = freezed,Object? physicalWidthMm = null,}) {
  return _then(_ImageTarget(
pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,pageNumber: null == pageNumber ? _self.pageNumber : pageNumber // ignore: cast_nullable_to_non_nullable
as int,imageTargetId: null == imageTargetId ? _self.imageTargetId : imageTargetId // ignore: cast_nullable_to_non_nullable
as String,referenceImageUrl: freezed == referenceImageUrl ? _self.referenceImageUrl : referenceImageUrl // ignore: cast_nullable_to_non_nullable
as String?,physicalWidthMm: null == physicalWidthMm ? _self.physicalWidthMm : physicalWidthMm // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ImageTargetManifest {

 String get storyId; int get version; List<ImageTarget> get targets;
/// Create a copy of ImageTargetManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageTargetManifestCopyWith<ImageTargetManifest> get copyWith => _$ImageTargetManifestCopyWithImpl<ImageTargetManifest>(this as ImageTargetManifest, _$identity);

  /// Serializes this ImageTargetManifest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageTargetManifest&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.version, version) || other.version == version)&&const DeepCollectionEquality().equals(other.targets, targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,storyId,version,const DeepCollectionEquality().hash(targets));

@override
String toString() {
  return 'ImageTargetManifest(storyId: $storyId, version: $version, targets: $targets)';
}


}

/// @nodoc
abstract mixin class $ImageTargetManifestCopyWith<$Res>  {
  factory $ImageTargetManifestCopyWith(ImageTargetManifest value, $Res Function(ImageTargetManifest) _then) = _$ImageTargetManifestCopyWithImpl;
@useResult
$Res call({
 String storyId, int version, List<ImageTarget> targets
});




}
/// @nodoc
class _$ImageTargetManifestCopyWithImpl<$Res>
    implements $ImageTargetManifestCopyWith<$Res> {
  _$ImageTargetManifestCopyWithImpl(this._self, this._then);

  final ImageTargetManifest _self;
  final $Res Function(ImageTargetManifest) _then;

/// Create a copy of ImageTargetManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? storyId = null,Object? version = null,Object? targets = null,}) {
  return _then(_self.copyWith(
storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as List<ImageTarget>,
  ));
}

}


/// Adds pattern-matching-related methods to [ImageTargetManifest].
extension ImageTargetManifestPatterns on ImageTargetManifest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ImageTargetManifest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ImageTargetManifest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ImageTargetManifest value)  $default,){
final _that = this;
switch (_that) {
case _ImageTargetManifest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ImageTargetManifest value)?  $default,){
final _that = this;
switch (_that) {
case _ImageTargetManifest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String storyId,  int version,  List<ImageTarget> targets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ImageTargetManifest() when $default != null:
return $default(_that.storyId,_that.version,_that.targets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String storyId,  int version,  List<ImageTarget> targets)  $default,) {final _that = this;
switch (_that) {
case _ImageTargetManifest():
return $default(_that.storyId,_that.version,_that.targets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String storyId,  int version,  List<ImageTarget> targets)?  $default,) {final _that = this;
switch (_that) {
case _ImageTargetManifest() when $default != null:
return $default(_that.storyId,_that.version,_that.targets);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ImageTargetManifest implements ImageTargetManifest {
  const _ImageTargetManifest({required this.storyId, required this.version, final  List<ImageTarget> targets = const <ImageTarget>[]}): _targets = targets;
  factory _ImageTargetManifest.fromJson(Map<String, dynamic> json) => _$ImageTargetManifestFromJson(json);

@override final  String storyId;
@override final  int version;
 final  List<ImageTarget> _targets;
@override@JsonKey() List<ImageTarget> get targets {
  if (_targets is EqualUnmodifiableListView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targets);
}


/// Create a copy of ImageTargetManifest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ImageTargetManifestCopyWith<_ImageTargetManifest> get copyWith => __$ImageTargetManifestCopyWithImpl<_ImageTargetManifest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ImageTargetManifestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ImageTargetManifest&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.version, version) || other.version == version)&&const DeepCollectionEquality().equals(other._targets, _targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,storyId,version,const DeepCollectionEquality().hash(_targets));

@override
String toString() {
  return 'ImageTargetManifest(storyId: $storyId, version: $version, targets: $targets)';
}


}

/// @nodoc
abstract mixin class _$ImageTargetManifestCopyWith<$Res> implements $ImageTargetManifestCopyWith<$Res> {
  factory _$ImageTargetManifestCopyWith(_ImageTargetManifest value, $Res Function(_ImageTargetManifest) _then) = __$ImageTargetManifestCopyWithImpl;
@override @useResult
$Res call({
 String storyId, int version, List<ImageTarget> targets
});




}
/// @nodoc
class __$ImageTargetManifestCopyWithImpl<$Res>
    implements _$ImageTargetManifestCopyWith<$Res> {
  __$ImageTargetManifestCopyWithImpl(this._self, this._then);

  final _ImageTargetManifest _self;
  final $Res Function(_ImageTargetManifest) _then;

/// Create a copy of ImageTargetManifest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? storyId = null,Object? version = null,Object? targets = null,}) {
  return _then(_ImageTargetManifest(
storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as List<ImageTarget>,
  ));
}


}

// dart format on
