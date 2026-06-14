// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'story_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StorySession {

 String get id; String get childProfileId; String get storyId; DateTime get startedAt; DateTime? get completedAt; int get lastPageNumber; SessionMode get mode;
/// Create a copy of StorySession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StorySessionCopyWith<StorySession> get copyWith => _$StorySessionCopyWithImpl<StorySession>(this as StorySession, _$identity);

  /// Serializes this StorySession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StorySession&&(identical(other.id, id) || other.id == id)&&(identical(other.childProfileId, childProfileId) || other.childProfileId == childProfileId)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.lastPageNumber, lastPageNumber) || other.lastPageNumber == lastPageNumber)&&(identical(other.mode, mode) || other.mode == mode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,childProfileId,storyId,startedAt,completedAt,lastPageNumber,mode);

@override
String toString() {
  return 'StorySession(id: $id, childProfileId: $childProfileId, storyId: $storyId, startedAt: $startedAt, completedAt: $completedAt, lastPageNumber: $lastPageNumber, mode: $mode)';
}


}

/// @nodoc
abstract mixin class $StorySessionCopyWith<$Res>  {
  factory $StorySessionCopyWith(StorySession value, $Res Function(StorySession) _then) = _$StorySessionCopyWithImpl;
@useResult
$Res call({
 String id, String childProfileId, String storyId, DateTime startedAt, DateTime? completedAt, int lastPageNumber, SessionMode mode
});




}
/// @nodoc
class _$StorySessionCopyWithImpl<$Res>
    implements $StorySessionCopyWith<$Res> {
  _$StorySessionCopyWithImpl(this._self, this._then);

  final StorySession _self;
  final $Res Function(StorySession) _then;

/// Create a copy of StorySession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? childProfileId = null,Object? storyId = null,Object? startedAt = null,Object? completedAt = freezed,Object? lastPageNumber = null,Object? mode = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,childProfileId: null == childProfileId ? _self.childProfileId : childProfileId // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastPageNumber: null == lastPageNumber ? _self.lastPageNumber : lastPageNumber // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as SessionMode,
  ));
}

}


/// Adds pattern-matching-related methods to [StorySession].
extension StorySessionPatterns on StorySession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StorySession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StorySession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StorySession value)  $default,){
final _that = this;
switch (_that) {
case _StorySession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StorySession value)?  $default,){
final _that = this;
switch (_that) {
case _StorySession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String childProfileId,  String storyId,  DateTime startedAt,  DateTime? completedAt,  int lastPageNumber,  SessionMode mode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StorySession() when $default != null:
return $default(_that.id,_that.childProfileId,_that.storyId,_that.startedAt,_that.completedAt,_that.lastPageNumber,_that.mode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String childProfileId,  String storyId,  DateTime startedAt,  DateTime? completedAt,  int lastPageNumber,  SessionMode mode)  $default,) {final _that = this;
switch (_that) {
case _StorySession():
return $default(_that.id,_that.childProfileId,_that.storyId,_that.startedAt,_that.completedAt,_that.lastPageNumber,_that.mode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String childProfileId,  String storyId,  DateTime startedAt,  DateTime? completedAt,  int lastPageNumber,  SessionMode mode)?  $default,) {final _that = this;
switch (_that) {
case _StorySession() when $default != null:
return $default(_that.id,_that.childProfileId,_that.storyId,_that.startedAt,_that.completedAt,_that.lastPageNumber,_that.mode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StorySession extends StorySession {
  const _StorySession({required this.id, required this.childProfileId, required this.storyId, required this.startedAt, this.completedAt, this.lastPageNumber = 0, this.mode = SessionMode.library}): super._();
  factory _StorySession.fromJson(Map<String, dynamic> json) => _$StorySessionFromJson(json);

@override final  String id;
@override final  String childProfileId;
@override final  String storyId;
@override final  DateTime startedAt;
@override final  DateTime? completedAt;
@override@JsonKey() final  int lastPageNumber;
@override@JsonKey() final  SessionMode mode;

/// Create a copy of StorySession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StorySessionCopyWith<_StorySession> get copyWith => __$StorySessionCopyWithImpl<_StorySession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StorySessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StorySession&&(identical(other.id, id) || other.id == id)&&(identical(other.childProfileId, childProfileId) || other.childProfileId == childProfileId)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.lastPageNumber, lastPageNumber) || other.lastPageNumber == lastPageNumber)&&(identical(other.mode, mode) || other.mode == mode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,childProfileId,storyId,startedAt,completedAt,lastPageNumber,mode);

@override
String toString() {
  return 'StorySession(id: $id, childProfileId: $childProfileId, storyId: $storyId, startedAt: $startedAt, completedAt: $completedAt, lastPageNumber: $lastPageNumber, mode: $mode)';
}


}

/// @nodoc
abstract mixin class _$StorySessionCopyWith<$Res> implements $StorySessionCopyWith<$Res> {
  factory _$StorySessionCopyWith(_StorySession value, $Res Function(_StorySession) _then) = __$StorySessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String childProfileId, String storyId, DateTime startedAt, DateTime? completedAt, int lastPageNumber, SessionMode mode
});




}
/// @nodoc
class __$StorySessionCopyWithImpl<$Res>
    implements _$StorySessionCopyWith<$Res> {
  __$StorySessionCopyWithImpl(this._self, this._then);

  final _StorySession _self;
  final $Res Function(_StorySession) _then;

/// Create a copy of StorySession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? childProfileId = null,Object? storyId = null,Object? startedAt = null,Object? completedAt = freezed,Object? lastPageNumber = null,Object? mode = null,}) {
  return _then(_StorySession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,childProfileId: null == childProfileId ? _self.childProfileId : childProfileId // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastPageNumber: null == lastPageNumber ? _self.lastPageNumber : lastPageNumber // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as SessionMode,
  ));
}


}

// dart format on
