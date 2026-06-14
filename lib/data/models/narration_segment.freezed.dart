// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'narration_segment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NarrationSegment {

 String get id; String get storyId; String get pageId;/// `narrator` or a character key (§4.2 `speaker_key`).
 String get speakerKey; String get text;/// Licensed/platform-approved voice reference (§7.1.3). Never voice cloning.
 String get voiceId; String? get emotion;/// Playback speed multiplier (`speed NUMERIC(4,2)` in §10).
 double get speed;/// Rendered audio clip; served via signed URL in production (§9.5.4).
/// Null in this slice falls back to DEV-ONLY on-device TTS.
 String? get audioAssetId;/// Segment timing for gapless playback + highlight sync (§4.2).
 int get startMs; int get endMs;/// Playback order within the page (`sort_order NOT NULL`).
 int get sortOrder;
/// Create a copy of NarrationSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NarrationSegmentCopyWith<NarrationSegment> get copyWith => _$NarrationSegmentCopyWithImpl<NarrationSegment>(this as NarrationSegment, _$identity);

  /// Serializes this NarrationSegment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NarrationSegment&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.speakerKey, speakerKey) || other.speakerKey == speakerKey)&&(identical(other.text, text) || other.text == text)&&(identical(other.voiceId, voiceId) || other.voiceId == voiceId)&&(identical(other.emotion, emotion) || other.emotion == emotion)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.audioAssetId, audioAssetId) || other.audioAssetId == audioAssetId)&&(identical(other.startMs, startMs) || other.startMs == startMs)&&(identical(other.endMs, endMs) || other.endMs == endMs)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageId,speakerKey,text,voiceId,emotion,speed,audioAssetId,startMs,endMs,sortOrder);

@override
String toString() {
  return 'NarrationSegment(id: $id, storyId: $storyId, pageId: $pageId, speakerKey: $speakerKey, text: $text, voiceId: $voiceId, emotion: $emotion, speed: $speed, audioAssetId: $audioAssetId, startMs: $startMs, endMs: $endMs, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class $NarrationSegmentCopyWith<$Res>  {
  factory $NarrationSegmentCopyWith(NarrationSegment value, $Res Function(NarrationSegment) _then) = _$NarrationSegmentCopyWithImpl;
@useResult
$Res call({
 String id, String storyId, String pageId, String speakerKey, String text, String voiceId, String? emotion, double speed, String? audioAssetId, int startMs, int endMs, int sortOrder
});




}
/// @nodoc
class _$NarrationSegmentCopyWithImpl<$Res>
    implements $NarrationSegmentCopyWith<$Res> {
  _$NarrationSegmentCopyWithImpl(this._self, this._then);

  final NarrationSegment _self;
  final $Res Function(NarrationSegment) _then;

/// Create a copy of NarrationSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? storyId = null,Object? pageId = null,Object? speakerKey = null,Object? text = null,Object? voiceId = null,Object? emotion = freezed,Object? speed = null,Object? audioAssetId = freezed,Object? startMs = null,Object? endMs = null,Object? sortOrder = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,speakerKey: null == speakerKey ? _self.speakerKey : speakerKey // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,voiceId: null == voiceId ? _self.voiceId : voiceId // ignore: cast_nullable_to_non_nullable
as String,emotion: freezed == emotion ? _self.emotion : emotion // ignore: cast_nullable_to_non_nullable
as String?,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,audioAssetId: freezed == audioAssetId ? _self.audioAssetId : audioAssetId // ignore: cast_nullable_to_non_nullable
as String?,startMs: null == startMs ? _self.startMs : startMs // ignore: cast_nullable_to_non_nullable
as int,endMs: null == endMs ? _self.endMs : endMs // ignore: cast_nullable_to_non_nullable
as int,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [NarrationSegment].
extension NarrationSegmentPatterns on NarrationSegment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NarrationSegment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NarrationSegment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NarrationSegment value)  $default,){
final _that = this;
switch (_that) {
case _NarrationSegment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NarrationSegment value)?  $default,){
final _that = this;
switch (_that) {
case _NarrationSegment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String storyId,  String pageId,  String speakerKey,  String text,  String voiceId,  String? emotion,  double speed,  String? audioAssetId,  int startMs,  int endMs,  int sortOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NarrationSegment() when $default != null:
return $default(_that.id,_that.storyId,_that.pageId,_that.speakerKey,_that.text,_that.voiceId,_that.emotion,_that.speed,_that.audioAssetId,_that.startMs,_that.endMs,_that.sortOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String storyId,  String pageId,  String speakerKey,  String text,  String voiceId,  String? emotion,  double speed,  String? audioAssetId,  int startMs,  int endMs,  int sortOrder)  $default,) {final _that = this;
switch (_that) {
case _NarrationSegment():
return $default(_that.id,_that.storyId,_that.pageId,_that.speakerKey,_that.text,_that.voiceId,_that.emotion,_that.speed,_that.audioAssetId,_that.startMs,_that.endMs,_that.sortOrder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String storyId,  String pageId,  String speakerKey,  String text,  String voiceId,  String? emotion,  double speed,  String? audioAssetId,  int startMs,  int endMs,  int sortOrder)?  $default,) {final _that = this;
switch (_that) {
case _NarrationSegment() when $default != null:
return $default(_that.id,_that.storyId,_that.pageId,_that.speakerKey,_that.text,_that.voiceId,_that.emotion,_that.speed,_that.audioAssetId,_that.startMs,_that.endMs,_that.sortOrder);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NarrationSegment extends NarrationSegment {
  const _NarrationSegment({required this.id, required this.storyId, required this.pageId, required this.speakerKey, required this.text, required this.voiceId, this.emotion, this.speed = 1.0, this.audioAssetId, this.startMs = 0, this.endMs = 0, required this.sortOrder}): super._();
  factory _NarrationSegment.fromJson(Map<String, dynamic> json) => _$NarrationSegmentFromJson(json);

@override final  String id;
@override final  String storyId;
@override final  String pageId;
/// `narrator` or a character key (§4.2 `speaker_key`).
@override final  String speakerKey;
@override final  String text;
/// Licensed/platform-approved voice reference (§7.1.3). Never voice cloning.
@override final  String voiceId;
@override final  String? emotion;
/// Playback speed multiplier (`speed NUMERIC(4,2)` in §10).
@override@JsonKey() final  double speed;
/// Rendered audio clip; served via signed URL in production (§9.5.4).
/// Null in this slice falls back to DEV-ONLY on-device TTS.
@override final  String? audioAssetId;
/// Segment timing for gapless playback + highlight sync (§4.2).
@override@JsonKey() final  int startMs;
@override@JsonKey() final  int endMs;
/// Playback order within the page (`sort_order NOT NULL`).
@override final  int sortOrder;

/// Create a copy of NarrationSegment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NarrationSegmentCopyWith<_NarrationSegment> get copyWith => __$NarrationSegmentCopyWithImpl<_NarrationSegment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NarrationSegmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NarrationSegment&&(identical(other.id, id) || other.id == id)&&(identical(other.storyId, storyId) || other.storyId == storyId)&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.speakerKey, speakerKey) || other.speakerKey == speakerKey)&&(identical(other.text, text) || other.text == text)&&(identical(other.voiceId, voiceId) || other.voiceId == voiceId)&&(identical(other.emotion, emotion) || other.emotion == emotion)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.audioAssetId, audioAssetId) || other.audioAssetId == audioAssetId)&&(identical(other.startMs, startMs) || other.startMs == startMs)&&(identical(other.endMs, endMs) || other.endMs == endMs)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,storyId,pageId,speakerKey,text,voiceId,emotion,speed,audioAssetId,startMs,endMs,sortOrder);

@override
String toString() {
  return 'NarrationSegment(id: $id, storyId: $storyId, pageId: $pageId, speakerKey: $speakerKey, text: $text, voiceId: $voiceId, emotion: $emotion, speed: $speed, audioAssetId: $audioAssetId, startMs: $startMs, endMs: $endMs, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class _$NarrationSegmentCopyWith<$Res> implements $NarrationSegmentCopyWith<$Res> {
  factory _$NarrationSegmentCopyWith(_NarrationSegment value, $Res Function(_NarrationSegment) _then) = __$NarrationSegmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String storyId, String pageId, String speakerKey, String text, String voiceId, String? emotion, double speed, String? audioAssetId, int startMs, int endMs, int sortOrder
});




}
/// @nodoc
class __$NarrationSegmentCopyWithImpl<$Res>
    implements _$NarrationSegmentCopyWith<$Res> {
  __$NarrationSegmentCopyWithImpl(this._self, this._then);

  final _NarrationSegment _self;
  final $Res Function(_NarrationSegment) _then;

/// Create a copy of NarrationSegment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? storyId = null,Object? pageId = null,Object? speakerKey = null,Object? text = null,Object? voiceId = null,Object? emotion = freezed,Object? speed = null,Object? audioAssetId = freezed,Object? startMs = null,Object? endMs = null,Object? sortOrder = null,}) {
  return _then(_NarrationSegment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,storyId: null == storyId ? _self.storyId : storyId // ignore: cast_nullable_to_non_nullable
as String,pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,speakerKey: null == speakerKey ? _self.speakerKey : speakerKey // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,voiceId: null == voiceId ? _self.voiceId : voiceId // ignore: cast_nullable_to_non_nullable
as String,emotion: freezed == emotion ? _self.emotion : emotion // ignore: cast_nullable_to_non_nullable
as String?,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,audioAssetId: freezed == audioAssetId ? _self.audioAssetId : audioAssetId // ignore: cast_nullable_to_non_nullable
as String?,startMs: null == startMs ? _self.startMs : startMs // ignore: cast_nullable_to_non_nullable
as int,endMs: null == endMs ? _self.endMs : endMs // ignore: cast_nullable_to_non_nullable
as int,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
