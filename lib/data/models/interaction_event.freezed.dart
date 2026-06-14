// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$InteractionEvent {

 String get id; String get storySessionId;/// e.g. `story_started`, `page_viewed`, `question_answered`,
/// `ar_interaction`, `story_completed` (§16.1 must-have events §8.3).
 String get eventType; String? get pageId; Map<String, dynamic> get payload; DateTime get createdAt;
/// Create a copy of InteractionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionEventCopyWith<InteractionEvent> get copyWith => _$InteractionEventCopyWithImpl<InteractionEvent>(this as InteractionEvent, _$identity);

  /// Serializes this InteractionEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.storySessionId, storySessionId) || other.storySessionId == storySessionId)&&(identical(other.eventType, eventType) || other.eventType == eventType)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&const DeepCollectionEquality().equals(other.payload, payload)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storySessionId,eventType,pageId,const DeepCollectionEquality().hash(payload),createdAt);

@override
String toString() {
  return 'InteractionEvent(id: $id, storySessionId: $storySessionId, eventType: $eventType, pageId: $pageId, payload: $payload, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $InteractionEventCopyWith<$Res>  {
  factory $InteractionEventCopyWith(InteractionEvent value, $Res Function(InteractionEvent) _then) = _$InteractionEventCopyWithImpl;
@useResult
$Res call({
 String id, String storySessionId, String eventType, String? pageId, Map<String, dynamic> payload, DateTime createdAt
});




}
/// @nodoc
class _$InteractionEventCopyWithImpl<$Res>
    implements $InteractionEventCopyWith<$Res> {
  _$InteractionEventCopyWithImpl(this._self, this._then);

  final InteractionEvent _self;
  final $Res Function(InteractionEvent) _then;

/// Create a copy of InteractionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? storySessionId = null,Object? eventType = null,Object? pageId = freezed,Object? payload = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storySessionId: null == storySessionId ? _self.storySessionId : storySessionId // ignore: cast_nullable_to_non_nullable
as String,eventType: null == eventType ? _self.eventType : eventType // ignore: cast_nullable_to_non_nullable
as String,pageId: freezed == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String?,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionEvent].
extension InteractionEventPatterns on InteractionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionEvent value)  $default,){
final _that = this;
switch (_that) {
case _InteractionEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionEvent value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String storySessionId,  String eventType,  String? pageId,  Map<String, dynamic> payload,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionEvent() when $default != null:
return $default(_that.id,_that.storySessionId,_that.eventType,_that.pageId,_that.payload,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String storySessionId,  String eventType,  String? pageId,  Map<String, dynamic> payload,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _InteractionEvent():
return $default(_that.id,_that.storySessionId,_that.eventType,_that.pageId,_that.payload,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String storySessionId,  String eventType,  String? pageId,  Map<String, dynamic> payload,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _InteractionEvent() when $default != null:
return $default(_that.id,_that.storySessionId,_that.eventType,_that.pageId,_that.payload,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InteractionEvent implements InteractionEvent {
  const _InteractionEvent({required this.id, required this.storySessionId, required this.eventType, this.pageId, final  Map<String, dynamic> payload = const <String, dynamic>{}, required this.createdAt}): _payload = payload;
  factory _InteractionEvent.fromJson(Map<String, dynamic> json) => _$InteractionEventFromJson(json);

@override final  String id;
@override final  String storySessionId;
/// e.g. `story_started`, `page_viewed`, `question_answered`,
/// `ar_interaction`, `story_completed` (§16.1 must-have events §8.3).
@override final  String eventType;
@override final  String? pageId;
 final  Map<String, dynamic> _payload;
@override@JsonKey() Map<String, dynamic> get payload {
  if (_payload is EqualUnmodifiableMapView) return _payload;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_payload);
}

@override final  DateTime createdAt;

/// Create a copy of InteractionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionEventCopyWith<_InteractionEvent> get copyWith => __$InteractionEventCopyWithImpl<_InteractionEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InteractionEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.storySessionId, storySessionId) || other.storySessionId == storySessionId)&&(identical(other.eventType, eventType) || other.eventType == eventType)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&const DeepCollectionEquality().equals(other._payload, _payload)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storySessionId,eventType,pageId,const DeepCollectionEquality().hash(_payload),createdAt);

@override
String toString() {
  return 'InteractionEvent(id: $id, storySessionId: $storySessionId, eventType: $eventType, pageId: $pageId, payload: $payload, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$InteractionEventCopyWith<$Res> implements $InteractionEventCopyWith<$Res> {
  factory _$InteractionEventCopyWith(_InteractionEvent value, $Res Function(_InteractionEvent) _then) = __$InteractionEventCopyWithImpl;
@override @useResult
$Res call({
 String id, String storySessionId, String eventType, String? pageId, Map<String, dynamic> payload, DateTime createdAt
});




}
/// @nodoc
class __$InteractionEventCopyWithImpl<$Res>
    implements _$InteractionEventCopyWith<$Res> {
  __$InteractionEventCopyWithImpl(this._self, this._then);

  final _InteractionEvent _self;
  final $Res Function(_InteractionEvent) _then;

/// Create a copy of InteractionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? storySessionId = null,Object? eventType = null,Object? pageId = freezed,Object? payload = null,Object? createdAt = null,}) {
  return _then(_InteractionEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storySessionId: null == storySessionId ? _self.storySessionId : storySessionId // ignore: cast_nullable_to_non_nullable
as String,eventType: null == eventType ? _self.eventType : eventType // ignore: cast_nullable_to_non_nullable
as String,pageId: freezed == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String?,payload: null == payload ? _self._payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
