// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ar_scene.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ArVector3 {

 double get x; double get y; double get z;
/// Create a copy of ArVector3
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArVector3CopyWith<ArVector3> get copyWith => _$ArVector3CopyWithImpl<ArVector3>(this as ArVector3, _$identity);

  /// Serializes this ArVector3 to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArVector3&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.z, z) || other.z == z));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y,z);

@override
String toString() {
  return 'ArVector3(x: $x, y: $y, z: $z)';
}


}

/// @nodoc
abstract mixin class $ArVector3CopyWith<$Res>  {
  factory $ArVector3CopyWith(ArVector3 value, $Res Function(ArVector3) _then) = _$ArVector3CopyWithImpl;
@useResult
$Res call({
 double x, double y, double z
});




}
/// @nodoc
class _$ArVector3CopyWithImpl<$Res>
    implements $ArVector3CopyWith<$Res> {
  _$ArVector3CopyWithImpl(this._self, this._then);

  final ArVector3 _self;
  final $Res Function(ArVector3) _then;

/// Create a copy of ArVector3
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? x = null,Object? y = null,Object? z = null,}) {
  return _then(_self.copyWith(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,z: null == z ? _self.z : z // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [ArVector3].
extension ArVector3Patterns on ArVector3 {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArVector3 value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArVector3() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArVector3 value)  $default,){
final _that = this;
switch (_that) {
case _ArVector3():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArVector3 value)?  $default,){
final _that = this;
switch (_that) {
case _ArVector3() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double x,  double y,  double z)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArVector3() when $default != null:
return $default(_that.x,_that.y,_that.z);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double x,  double y,  double z)  $default,) {final _that = this;
switch (_that) {
case _ArVector3():
return $default(_that.x,_that.y,_that.z);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double x,  double y,  double z)?  $default,) {final _that = this;
switch (_that) {
case _ArVector3() when $default != null:
return $default(_that.x,_that.y,_that.z);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArVector3 implements ArVector3 {
  const _ArVector3({this.x = 0.0, this.y = 0.0, this.z = 0.0});
  factory _ArVector3.fromJson(Map<String, dynamic> json) => _$ArVector3FromJson(json);

@override@JsonKey() final  double x;
@override@JsonKey() final  double y;
@override@JsonKey() final  double z;

/// Create a copy of ArVector3
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArVector3CopyWith<_ArVector3> get copyWith => __$ArVector3CopyWithImpl<_ArVector3>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArVector3ToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArVector3&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.z, z) || other.z == z));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y,z);

@override
String toString() {
  return 'ArVector3(x: $x, y: $y, z: $z)';
}


}

/// @nodoc
abstract mixin class _$ArVector3CopyWith<$Res> implements $ArVector3CopyWith<$Res> {
  factory _$ArVector3CopyWith(_ArVector3 value, $Res Function(_ArVector3) _then) = __$ArVector3CopyWithImpl;
@override @useResult
$Res call({
 double x, double y, double z
});




}
/// @nodoc
class __$ArVector3CopyWithImpl<$Res>
    implements _$ArVector3CopyWith<$Res> {
  __$ArVector3CopyWithImpl(this._self, this._then);

  final _ArVector3 _self;
  final $Res Function(_ArVector3) _then;

/// Create a copy of ArVector3
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,Object? z = null,}) {
  return _then(_ArVector3(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,z: null == z ? _self.z : z // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$ArSceneAsset {

 String get assetId; ArAssetType get type; ArVector3 get position; double get scale; String get defaultAnimation;/// Local/CDN image used to render a 2D character/object overlay.
 String? get imageAsset;
/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArSceneAssetCopyWith<ArSceneAsset> get copyWith => _$ArSceneAssetCopyWithImpl<ArSceneAsset>(this as ArSceneAsset, _$identity);

  /// Serializes this ArSceneAsset to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArSceneAsset&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.type, type) || other.type == type)&&(identical(other.position, position) || other.position == position)&&(identical(other.scale, scale) || other.scale == scale)&&(identical(other.defaultAnimation, defaultAnimation) || other.defaultAnimation == defaultAnimation)&&(identical(other.imageAsset, imageAsset) || other.imageAsset == imageAsset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,assetId,type,position,scale,defaultAnimation,imageAsset);

@override
String toString() {
  return 'ArSceneAsset(assetId: $assetId, type: $type, position: $position, scale: $scale, defaultAnimation: $defaultAnimation, imageAsset: $imageAsset)';
}


}

/// @nodoc
abstract mixin class $ArSceneAssetCopyWith<$Res>  {
  factory $ArSceneAssetCopyWith(ArSceneAsset value, $Res Function(ArSceneAsset) _then) = _$ArSceneAssetCopyWithImpl;
@useResult
$Res call({
 String assetId, ArAssetType type, ArVector3 position, double scale, String defaultAnimation, String? imageAsset
});


$ArVector3CopyWith<$Res> get position;

}
/// @nodoc
class _$ArSceneAssetCopyWithImpl<$Res>
    implements $ArSceneAssetCopyWith<$Res> {
  _$ArSceneAssetCopyWithImpl(this._self, this._then);

  final ArSceneAsset _self;
  final $Res Function(ArSceneAsset) _then;

/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? assetId = null,Object? type = null,Object? position = null,Object? scale = null,Object? defaultAnimation = null,Object? imageAsset = freezed,}) {
  return _then(_self.copyWith(
assetId: null == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ArAssetType,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as ArVector3,scale: null == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double,defaultAnimation: null == defaultAnimation ? _self.defaultAnimation : defaultAnimation // ignore: cast_nullable_to_non_nullable
as String,imageAsset: freezed == imageAsset ? _self.imageAsset : imageAsset // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArVector3CopyWith<$Res> get position {
  
  return $ArVector3CopyWith<$Res>(_self.position, (value) {
    return _then(_self.copyWith(position: value));
  });
}
}


/// Adds pattern-matching-related methods to [ArSceneAsset].
extension ArSceneAssetPatterns on ArSceneAsset {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArSceneAsset value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArSceneAsset() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArSceneAsset value)  $default,){
final _that = this;
switch (_that) {
case _ArSceneAsset():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArSceneAsset value)?  $default,){
final _that = this;
switch (_that) {
case _ArSceneAsset() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String assetId,  ArAssetType type,  ArVector3 position,  double scale,  String defaultAnimation,  String? imageAsset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArSceneAsset() when $default != null:
return $default(_that.assetId,_that.type,_that.position,_that.scale,_that.defaultAnimation,_that.imageAsset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String assetId,  ArAssetType type,  ArVector3 position,  double scale,  String defaultAnimation,  String? imageAsset)  $default,) {final _that = this;
switch (_that) {
case _ArSceneAsset():
return $default(_that.assetId,_that.type,_that.position,_that.scale,_that.defaultAnimation,_that.imageAsset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String assetId,  ArAssetType type,  ArVector3 position,  double scale,  String defaultAnimation,  String? imageAsset)?  $default,) {final _that = this;
switch (_that) {
case _ArSceneAsset() when $default != null:
return $default(_that.assetId,_that.type,_that.position,_that.scale,_that.defaultAnimation,_that.imageAsset);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArSceneAsset implements ArSceneAsset {
  const _ArSceneAsset({required this.assetId, required this.type, this.position = const ArVector3(), this.scale = 1.0, required this.defaultAnimation, this.imageAsset});
  factory _ArSceneAsset.fromJson(Map<String, dynamic> json) => _$ArSceneAssetFromJson(json);

@override final  String assetId;
@override final  ArAssetType type;
@override@JsonKey() final  ArVector3 position;
@override@JsonKey() final  double scale;
@override final  String defaultAnimation;
/// Local/CDN image used to render a 2D character/object overlay.
@override final  String? imageAsset;

/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArSceneAssetCopyWith<_ArSceneAsset> get copyWith => __$ArSceneAssetCopyWithImpl<_ArSceneAsset>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArSceneAssetToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArSceneAsset&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.type, type) || other.type == type)&&(identical(other.position, position) || other.position == position)&&(identical(other.scale, scale) || other.scale == scale)&&(identical(other.defaultAnimation, defaultAnimation) || other.defaultAnimation == defaultAnimation)&&(identical(other.imageAsset, imageAsset) || other.imageAsset == imageAsset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,assetId,type,position,scale,defaultAnimation,imageAsset);

@override
String toString() {
  return 'ArSceneAsset(assetId: $assetId, type: $type, position: $position, scale: $scale, defaultAnimation: $defaultAnimation, imageAsset: $imageAsset)';
}


}

/// @nodoc
abstract mixin class _$ArSceneAssetCopyWith<$Res> implements $ArSceneAssetCopyWith<$Res> {
  factory _$ArSceneAssetCopyWith(_ArSceneAsset value, $Res Function(_ArSceneAsset) _then) = __$ArSceneAssetCopyWithImpl;
@override @useResult
$Res call({
 String assetId, ArAssetType type, ArVector3 position, double scale, String defaultAnimation, String? imageAsset
});


@override $ArVector3CopyWith<$Res> get position;

}
/// @nodoc
class __$ArSceneAssetCopyWithImpl<$Res>
    implements _$ArSceneAssetCopyWith<$Res> {
  __$ArSceneAssetCopyWithImpl(this._self, this._then);

  final _ArSceneAsset _self;
  final $Res Function(_ArSceneAsset) _then;

/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? assetId = null,Object? type = null,Object? position = null,Object? scale = null,Object? defaultAnimation = null,Object? imageAsset = freezed,}) {
  return _then(_ArSceneAsset(
assetId: null == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ArAssetType,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as ArVector3,scale: null == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double,defaultAnimation: null == defaultAnimation ? _self.defaultAnimation : defaultAnimation // ignore: cast_nullable_to_non_nullable
as String,imageAsset: freezed == imageAsset ? _self.imageAsset : imageAsset // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ArSceneAsset
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArVector3CopyWith<$Res> get position {
  
  return $ArVector3CopyWith<$Res>(_self.position, (value) {
    return _then(_self.copyWith(position: value));
  });
}
}


/// @nodoc
mixin _$ArInteraction {

 ArTrigger get trigger; String get targetAssetId; ArAction get action;/// Narration segment to play when [action] is `play_audio_segment`,
/// linking a tap back to the audio engine (§4.2, §9.3.3).
 String? get audioSegmentId;
/// Create a copy of ArInteraction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArInteractionCopyWith<ArInteraction> get copyWith => _$ArInteractionCopyWithImpl<ArInteraction>(this as ArInteraction, _$identity);

  /// Serializes this ArInteraction to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArInteraction&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.targetAssetId, targetAssetId) || other.targetAssetId == targetAssetId)&&(identical(other.action, action) || other.action == action)&&(identical(other.audioSegmentId, audioSegmentId) || other.audioSegmentId == audioSegmentId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,trigger,targetAssetId,action,audioSegmentId);

@override
String toString() {
  return 'ArInteraction(trigger: $trigger, targetAssetId: $targetAssetId, action: $action, audioSegmentId: $audioSegmentId)';
}


}

/// @nodoc
abstract mixin class $ArInteractionCopyWith<$Res>  {
  factory $ArInteractionCopyWith(ArInteraction value, $Res Function(ArInteraction) _then) = _$ArInteractionCopyWithImpl;
@useResult
$Res call({
 ArTrigger trigger, String targetAssetId, ArAction action, String? audioSegmentId
});




}
/// @nodoc
class _$ArInteractionCopyWithImpl<$Res>
    implements $ArInteractionCopyWith<$Res> {
  _$ArInteractionCopyWithImpl(this._self, this._then);

  final ArInteraction _self;
  final $Res Function(ArInteraction) _then;

/// Create a copy of ArInteraction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? trigger = null,Object? targetAssetId = null,Object? action = null,Object? audioSegmentId = freezed,}) {
  return _then(_self.copyWith(
trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as ArTrigger,targetAssetId: null == targetAssetId ? _self.targetAssetId : targetAssetId // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ArAction,audioSegmentId: freezed == audioSegmentId ? _self.audioSegmentId : audioSegmentId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ArInteraction].
extension ArInteractionPatterns on ArInteraction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArInteraction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArInteraction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArInteraction value)  $default,){
final _that = this;
switch (_that) {
case _ArInteraction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArInteraction value)?  $default,){
final _that = this;
switch (_that) {
case _ArInteraction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ArTrigger trigger,  String targetAssetId,  ArAction action,  String? audioSegmentId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArInteraction() when $default != null:
return $default(_that.trigger,_that.targetAssetId,_that.action,_that.audioSegmentId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ArTrigger trigger,  String targetAssetId,  ArAction action,  String? audioSegmentId)  $default,) {final _that = this;
switch (_that) {
case _ArInteraction():
return $default(_that.trigger,_that.targetAssetId,_that.action,_that.audioSegmentId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ArTrigger trigger,  String targetAssetId,  ArAction action,  String? audioSegmentId)?  $default,) {final _that = this;
switch (_that) {
case _ArInteraction() when $default != null:
return $default(_that.trigger,_that.targetAssetId,_that.action,_that.audioSegmentId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArInteraction implements ArInteraction {
  const _ArInteraction({required this.trigger, required this.targetAssetId, required this.action, this.audioSegmentId});
  factory _ArInteraction.fromJson(Map<String, dynamic> json) => _$ArInteractionFromJson(json);

@override final  ArTrigger trigger;
@override final  String targetAssetId;
@override final  ArAction action;
/// Narration segment to play when [action] is `play_audio_segment`,
/// linking a tap back to the audio engine (§4.2, §9.3.3).
@override final  String? audioSegmentId;

/// Create a copy of ArInteraction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArInteractionCopyWith<_ArInteraction> get copyWith => __$ArInteractionCopyWithImpl<_ArInteraction>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArInteractionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArInteraction&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.targetAssetId, targetAssetId) || other.targetAssetId == targetAssetId)&&(identical(other.action, action) || other.action == action)&&(identical(other.audioSegmentId, audioSegmentId) || other.audioSegmentId == audioSegmentId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,trigger,targetAssetId,action,audioSegmentId);

@override
String toString() {
  return 'ArInteraction(trigger: $trigger, targetAssetId: $targetAssetId, action: $action, audioSegmentId: $audioSegmentId)';
}


}

/// @nodoc
abstract mixin class _$ArInteractionCopyWith<$Res> implements $ArInteractionCopyWith<$Res> {
  factory _$ArInteractionCopyWith(_ArInteraction value, $Res Function(_ArInteraction) _then) = __$ArInteractionCopyWithImpl;
@override @useResult
$Res call({
 ArTrigger trigger, String targetAssetId, ArAction action, String? audioSegmentId
});




}
/// @nodoc
class __$ArInteractionCopyWithImpl<$Res>
    implements _$ArInteractionCopyWith<$Res> {
  __$ArInteractionCopyWithImpl(this._self, this._then);

  final _ArInteraction _self;
  final $Res Function(_ArInteraction) _then;

/// Create a copy of ArInteraction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? trigger = null,Object? targetAssetId = null,Object? action = null,Object? audioSegmentId = freezed,}) {
  return _then(_ArInteraction(
trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as ArTrigger,targetAssetId: null == targetAssetId ? _self.targetAssetId : targetAssetId // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ArAction,audioSegmentId: freezed == audioSegmentId ? _self.audioSegmentId : audioSegmentId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ArSceneData {

 String get sceneId; ArAnchorType get anchorType; List<ArSceneAsset> get assets; List<ArInteraction> get interactions;
/// Create a copy of ArSceneData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArSceneDataCopyWith<ArSceneData> get copyWith => _$ArSceneDataCopyWithImpl<ArSceneData>(this as ArSceneData, _$identity);

  /// Serializes this ArSceneData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArSceneData&&(identical(other.sceneId, sceneId) || other.sceneId == sceneId)&&(identical(other.anchorType, anchorType) || other.anchorType == anchorType)&&const DeepCollectionEquality().equals(other.assets, assets)&&const DeepCollectionEquality().equals(other.interactions, interactions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sceneId,anchorType,const DeepCollectionEquality().hash(assets),const DeepCollectionEquality().hash(interactions));

@override
String toString() {
  return 'ArSceneData(sceneId: $sceneId, anchorType: $anchorType, assets: $assets, interactions: $interactions)';
}


}

/// @nodoc
abstract mixin class $ArSceneDataCopyWith<$Res>  {
  factory $ArSceneDataCopyWith(ArSceneData value, $Res Function(ArSceneData) _then) = _$ArSceneDataCopyWithImpl;
@useResult
$Res call({
 String sceneId, ArAnchorType anchorType, List<ArSceneAsset> assets, List<ArInteraction> interactions
});




}
/// @nodoc
class _$ArSceneDataCopyWithImpl<$Res>
    implements $ArSceneDataCopyWith<$Res> {
  _$ArSceneDataCopyWithImpl(this._self, this._then);

  final ArSceneData _self;
  final $Res Function(ArSceneData) _then;

/// Create a copy of ArSceneData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sceneId = null,Object? anchorType = null,Object? assets = null,Object? interactions = null,}) {
  return _then(_self.copyWith(
sceneId: null == sceneId ? _self.sceneId : sceneId // ignore: cast_nullable_to_non_nullable
as String,anchorType: null == anchorType ? _self.anchorType : anchorType // ignore: cast_nullable_to_non_nullable
as ArAnchorType,assets: null == assets ? _self.assets : assets // ignore: cast_nullable_to_non_nullable
as List<ArSceneAsset>,interactions: null == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as List<ArInteraction>,
  ));
}

}


/// Adds pattern-matching-related methods to [ArSceneData].
extension ArSceneDataPatterns on ArSceneData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArSceneData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArSceneData() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArSceneData value)  $default,){
final _that = this;
switch (_that) {
case _ArSceneData():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArSceneData value)?  $default,){
final _that = this;
switch (_that) {
case _ArSceneData() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sceneId,  ArAnchorType anchorType,  List<ArSceneAsset> assets,  List<ArInteraction> interactions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArSceneData() when $default != null:
return $default(_that.sceneId,_that.anchorType,_that.assets,_that.interactions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sceneId,  ArAnchorType anchorType,  List<ArSceneAsset> assets,  List<ArInteraction> interactions)  $default,) {final _that = this;
switch (_that) {
case _ArSceneData():
return $default(_that.sceneId,_that.anchorType,_that.assets,_that.interactions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sceneId,  ArAnchorType anchorType,  List<ArSceneAsset> assets,  List<ArInteraction> interactions)?  $default,) {final _that = this;
switch (_that) {
case _ArSceneData() when $default != null:
return $default(_that.sceneId,_that.anchorType,_that.assets,_that.interactions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArSceneData implements ArSceneData {
  const _ArSceneData({required this.sceneId, this.anchorType = ArAnchorType.imageTarget, final  List<ArSceneAsset> assets = const <ArSceneAsset>[], final  List<ArInteraction> interactions = const <ArInteraction>[]}): _assets = assets,_interactions = interactions;
  factory _ArSceneData.fromJson(Map<String, dynamic> json) => _$ArSceneDataFromJson(json);

@override final  String sceneId;
@override@JsonKey() final  ArAnchorType anchorType;
 final  List<ArSceneAsset> _assets;
@override@JsonKey() List<ArSceneAsset> get assets {
  if (_assets is EqualUnmodifiableListView) return _assets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_assets);
}

 final  List<ArInteraction> _interactions;
@override@JsonKey() List<ArInteraction> get interactions {
  if (_interactions is EqualUnmodifiableListView) return _interactions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_interactions);
}


/// Create a copy of ArSceneData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArSceneDataCopyWith<_ArSceneData> get copyWith => __$ArSceneDataCopyWithImpl<_ArSceneData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArSceneDataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArSceneData&&(identical(other.sceneId, sceneId) || other.sceneId == sceneId)&&(identical(other.anchorType, anchorType) || other.anchorType == anchorType)&&const DeepCollectionEquality().equals(other._assets, _assets)&&const DeepCollectionEquality().equals(other._interactions, _interactions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sceneId,anchorType,const DeepCollectionEquality().hash(_assets),const DeepCollectionEquality().hash(_interactions));

@override
String toString() {
  return 'ArSceneData(sceneId: $sceneId, anchorType: $anchorType, assets: $assets, interactions: $interactions)';
}


}

/// @nodoc
abstract mixin class _$ArSceneDataCopyWith<$Res> implements $ArSceneDataCopyWith<$Res> {
  factory _$ArSceneDataCopyWith(_ArSceneData value, $Res Function(_ArSceneData) _then) = __$ArSceneDataCopyWithImpl;
@override @useResult
$Res call({
 String sceneId, ArAnchorType anchorType, List<ArSceneAsset> assets, List<ArInteraction> interactions
});




}
/// @nodoc
class __$ArSceneDataCopyWithImpl<$Res>
    implements _$ArSceneDataCopyWith<$Res> {
  __$ArSceneDataCopyWithImpl(this._self, this._then);

  final _ArSceneData _self;
  final $Res Function(_ArSceneData) _then;

/// Create a copy of ArSceneData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sceneId = null,Object? anchorType = null,Object? assets = null,Object? interactions = null,}) {
  return _then(_ArSceneData(
sceneId: null == sceneId ? _self.sceneId : sceneId // ignore: cast_nullable_to_non_nullable
as String,anchorType: null == anchorType ? _self.anchorType : anchorType // ignore: cast_nullable_to_non_nullable
as ArAnchorType,assets: null == assets ? _self._assets : assets // ignore: cast_nullable_to_non_nullable
as List<ArSceneAsset>,interactions: null == interactions ? _self._interactions : interactions // ignore: cast_nullable_to_non_nullable
as List<ArInteraction>,
  ));
}


}


/// @nodoc
mixin _$ArScene {

 String get id; String get storyId;/// FK → `story_pages.id`; the join key from a recognized image target back
/// to this scene (§3.6).
 String get pageId; ArSceneData get sceneJson; ContentStatus get status;
/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArSceneCopyWith<ArScene> get copyWith => _$ArSceneCopyWithImpl<ArScene>(this as ArScene, _$identity);

  /// Serializes this ArScene to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArScene&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.sceneJson, sceneJson) || other.sceneJson == sceneJson)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageId,sceneJson,status);

@override
String toString() {
  return 'ArScene(id: $id, storyId: $storyId, pageId: $pageId, sceneJson: $sceneJson, status: $status)';
}


}

/// @nodoc
abstract mixin class $ArSceneCopyWith<$Res>  {
  factory $ArSceneCopyWith(ArScene value, $Res Function(ArScene) _then) = _$ArSceneCopyWithImpl;
@useResult
$Res call({
 String id, String storyId, String pageId, ArSceneData sceneJson, ContentStatus status
});


$ArSceneDataCopyWith<$Res> get sceneJson;

}
/// @nodoc
class _$ArSceneCopyWithImpl<$Res>
    implements $ArSceneCopyWith<$Res> {
  _$ArSceneCopyWithImpl(this._self, this._then);

  final ArScene _self;
  final $Res Function(ArScene) _then;

/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? storyId = null,Object? pageId = null,Object? sceneJson = null,Object? status = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,sceneJson: null == sceneJson ? _self.sceneJson : sceneJson // ignore: cast_nullable_to_non_nullable
as ArSceneData,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ContentStatus,
  ));
}
/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArSceneDataCopyWith<$Res> get sceneJson {
  
  return $ArSceneDataCopyWith<$Res>(_self.sceneJson, (value) {
    return _then(_self.copyWith(sceneJson: value));
  });
}
}


/// Adds pattern-matching-related methods to [ArScene].
extension ArScenePatterns on ArScene {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArScene value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArScene() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArScene value)  $default,){
final _that = this;
switch (_that) {
case _ArScene():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArScene value)?  $default,){
final _that = this;
switch (_that) {
case _ArScene() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String storyId,  String pageId,  ArSceneData sceneJson,  ContentStatus status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArScene() when $default != null:
return $default(_that.id,_that.storyId,_that.pageId,_that.sceneJson,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String storyId,  String pageId,  ArSceneData sceneJson,  ContentStatus status)  $default,) {final _that = this;
switch (_that) {
case _ArScene():
return $default(_that.id,_that.storyId,_that.pageId,_that.sceneJson,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String storyId,  String pageId,  ArSceneData sceneJson,  ContentStatus status)?  $default,) {final _that = this;
switch (_that) {
case _ArScene() when $default != null:
return $default(_that.id,_that.storyId,_that.pageId,_that.sceneJson,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArScene extends ArScene {
  const _ArScene({required this.id, required this.storyId, required this.pageId, required this.sceneJson, this.status = ContentStatus.published}): super._();
  factory _ArScene.fromJson(Map<String, dynamic> json) => _$ArSceneFromJson(json);

@override final  String id;
@override final  String storyId;
/// FK → `story_pages.id`; the join key from a recognized image target back
/// to this scene (§3.6).
@override final  String pageId;
@override final  ArSceneData sceneJson;
@override@JsonKey() final  ContentStatus status;

/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArSceneCopyWith<_ArScene> get copyWith => __$ArSceneCopyWithImpl<_ArScene>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArSceneToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArScene&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.sceneJson, sceneJson) || other.sceneJson == sceneJson)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageId,sceneJson,status);

@override
String toString() {
  return 'ArScene(id: $id, storyId: $storyId, pageId: $pageId, sceneJson: $sceneJson, status: $status)';
}


}

/// @nodoc
abstract mixin class _$ArSceneCopyWith<$Res> implements $ArSceneCopyWith<$Res> {
  factory _$ArSceneCopyWith(_ArScene value, $Res Function(_ArScene) _then) = __$ArSceneCopyWithImpl;
@override @useResult
$Res call({
 String id, String storyId, String pageId, ArSceneData sceneJson, ContentStatus status
});


@override $ArSceneDataCopyWith<$Res> get sceneJson;

}
/// @nodoc
class __$ArSceneCopyWithImpl<$Res>
    implements _$ArSceneCopyWith<$Res> {
  __$ArSceneCopyWithImpl(this._self, this._then);

  final _ArScene _self;
  final $Res Function(_ArScene) _then;

/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? storyId = null,Object? pageId = null,Object? sceneJson = null,Object? status = null,}) {
  return _then(_ArScene(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,sceneJson: null == sceneJson ? _self.sceneJson : sceneJson // ignore: cast_nullable_to_non_nullable
as ArSceneData,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ContentStatus,
  ));
}

/// Create a copy of ArScene
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ArSceneDataCopyWith<$Res> get sceneJson {
  
  return $ArSceneDataCopyWith<$Res>(_self.sceneJson, (value) {
    return _then(_self.copyWith(sceneJson: value));
  });
}
}

// dart format on
