// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reading_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ReadingSettings {

/// Narration speed multiplier applied on top of per-segment speed.
 double get voiceSpeed; double get soundEffectsVolume; double get backgroundMusicVolume; String get languageCode; bool get bedtimeModeDefault;
/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadingSettingsCopyWith<ReadingSettings> get copyWith => _$ReadingSettingsCopyWithImpl<ReadingSettings>(this as ReadingSettings, _$identity);

  /// Serializes this ReadingSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadingSettings&&(identical(other.voiceSpeed, voiceSpeed) || other.voiceSpeed == voiceSpeed)&&(identical(other.soundEffectsVolume, soundEffectsVolume) || other.soundEffectsVolume == soundEffectsVolume)&&(identical(other.backgroundMusicVolume, backgroundMusicVolume) || other.backgroundMusicVolume == backgroundMusicVolume)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.bedtimeModeDefault, bedtimeModeDefault) || other.bedtimeModeDefault == bedtimeModeDefault));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,voiceSpeed,soundEffectsVolume,backgroundMusicVolume,languageCode,bedtimeModeDefault);

@override
String toString() {
  return 'ReadingSettings(voiceSpeed: $voiceSpeed, soundEffectsVolume: $soundEffectsVolume, backgroundMusicVolume: $backgroundMusicVolume, languageCode: $languageCode, bedtimeModeDefault: $bedtimeModeDefault)';
}


}

/// @nodoc
abstract mixin class $ReadingSettingsCopyWith<$Res>  {
  factory $ReadingSettingsCopyWith(ReadingSettings value, $Res Function(ReadingSettings) _then) = _$ReadingSettingsCopyWithImpl;
@useResult
$Res call({
 double voiceSpeed, double soundEffectsVolume, double backgroundMusicVolume, String languageCode, bool bedtimeModeDefault
});




}
/// @nodoc
class _$ReadingSettingsCopyWithImpl<$Res>
    implements $ReadingSettingsCopyWith<$Res> {
  _$ReadingSettingsCopyWithImpl(this._self, this._then);

  final ReadingSettings _self;
  final $Res Function(ReadingSettings) _then;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? voiceSpeed = null,Object? soundEffectsVolume = null,Object? backgroundMusicVolume = null,Object? languageCode = null,Object? bedtimeModeDefault = null,}) {
  return _then(_self.copyWith(
voiceSpeed: null == voiceSpeed ? _self.voiceSpeed : voiceSpeed // ignore: cast_nullable_to_non_nullable
as double,soundEffectsVolume: null == soundEffectsVolume ? _self.soundEffectsVolume : soundEffectsVolume // ignore: cast_nullable_to_non_nullable
as double,backgroundMusicVolume: null == backgroundMusicVolume ? _self.backgroundMusicVolume : backgroundMusicVolume // ignore: cast_nullable_to_non_nullable
as double,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,bedtimeModeDefault: null == bedtimeModeDefault ? _self.bedtimeModeDefault : bedtimeModeDefault // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ReadingSettings].
extension ReadingSettingsPatterns on ReadingSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadingSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadingSettings value)  $default,){
final _that = this;
switch (_that) {
case _ReadingSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadingSettings value)?  $default,){
final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double voiceSpeed,  double soundEffectsVolume,  double backgroundMusicVolume,  String languageCode,  bool bedtimeModeDefault)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.voiceSpeed,_that.soundEffectsVolume,_that.backgroundMusicVolume,_that.languageCode,_that.bedtimeModeDefault);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double voiceSpeed,  double soundEffectsVolume,  double backgroundMusicVolume,  String languageCode,  bool bedtimeModeDefault)  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings():
return $default(_that.voiceSpeed,_that.soundEffectsVolume,_that.backgroundMusicVolume,_that.languageCode,_that.bedtimeModeDefault);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double voiceSpeed,  double soundEffectsVolume,  double backgroundMusicVolume,  String languageCode,  bool bedtimeModeDefault)?  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.voiceSpeed,_that.soundEffectsVolume,_that.backgroundMusicVolume,_that.languageCode,_that.bedtimeModeDefault);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReadingSettings extends ReadingSettings {
  const _ReadingSettings({this.voiceSpeed = 1.0, this.soundEffectsVolume = 0.6, this.backgroundMusicVolume = 0.4, this.languageCode = 'en', this.bedtimeModeDefault = false}): super._();
  factory _ReadingSettings.fromJson(Map<String, dynamic> json) => _$ReadingSettingsFromJson(json);

/// Narration speed multiplier applied on top of per-segment speed.
@override@JsonKey() final  double voiceSpeed;
@override@JsonKey() final  double soundEffectsVolume;
@override@JsonKey() final  double backgroundMusicVolume;
@override@JsonKey() final  String languageCode;
@override@JsonKey() final  bool bedtimeModeDefault;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadingSettingsCopyWith<_ReadingSettings> get copyWith => __$ReadingSettingsCopyWithImpl<_ReadingSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReadingSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadingSettings&&(identical(other.voiceSpeed, voiceSpeed) || other.voiceSpeed == voiceSpeed)&&(identical(other.soundEffectsVolume, soundEffectsVolume) || other.soundEffectsVolume == soundEffectsVolume)&&(identical(other.backgroundMusicVolume, backgroundMusicVolume) || other.backgroundMusicVolume == backgroundMusicVolume)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.bedtimeModeDefault, bedtimeModeDefault) || other.bedtimeModeDefault == bedtimeModeDefault));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,voiceSpeed,soundEffectsVolume,backgroundMusicVolume,languageCode,bedtimeModeDefault);

@override
String toString() {
  return 'ReadingSettings(voiceSpeed: $voiceSpeed, soundEffectsVolume: $soundEffectsVolume, backgroundMusicVolume: $backgroundMusicVolume, languageCode: $languageCode, bedtimeModeDefault: $bedtimeModeDefault)';
}


}

/// @nodoc
abstract mixin class _$ReadingSettingsCopyWith<$Res> implements $ReadingSettingsCopyWith<$Res> {
  factory _$ReadingSettingsCopyWith(_ReadingSettings value, $Res Function(_ReadingSettings) _then) = __$ReadingSettingsCopyWithImpl;
@override @useResult
$Res call({
 double voiceSpeed, double soundEffectsVolume, double backgroundMusicVolume, String languageCode, bool bedtimeModeDefault
});




}
/// @nodoc
class __$ReadingSettingsCopyWithImpl<$Res>
    implements _$ReadingSettingsCopyWith<$Res> {
  __$ReadingSettingsCopyWithImpl(this._self, this._then);

  final _ReadingSettings _self;
  final $Res Function(_ReadingSettings) _then;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? voiceSpeed = null,Object? soundEffectsVolume = null,Object? backgroundMusicVolume = null,Object? languageCode = null,Object? bedtimeModeDefault = null,}) {
  return _then(_ReadingSettings(
voiceSpeed: null == voiceSpeed ? _self.voiceSpeed : voiceSpeed // ignore: cast_nullable_to_non_nullable
as double,soundEffectsVolume: null == soundEffectsVolume ? _self.soundEffectsVolume : soundEffectsVolume // ignore: cast_nullable_to_non_nullable
as double,backgroundMusicVolume: null == backgroundMusicVolume ? _self.backgroundMusicVolume : backgroundMusicVolume // ignore: cast_nullable_to_non_nullable
as double,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,bedtimeModeDefault: null == bedtimeModeDefault ? _self.bedtimeModeDefault : bedtimeModeDefault // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
