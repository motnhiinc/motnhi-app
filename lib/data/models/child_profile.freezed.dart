// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'child_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChildProfile {

 String get id;/// FK → `users.id`. Single implicit local parent in this offline slice.
 String get userId; String? get nickname; AgeBand get ageBand; String get languageCode; bool get bedtimeModeDefault; bool get microphoneEnabled; bool get arEnabled;
/// Create a copy of ChildProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChildProfileCopyWith<ChildProfile> get copyWith => _$ChildProfileCopyWithImpl<ChildProfile>(this as ChildProfile, _$identity);

  /// Serializes this ChildProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChildProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.ageBand, ageBand) || other.ageBand == ageBand)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.bedtimeModeDefault, bedtimeModeDefault) || other.bedtimeModeDefault == bedtimeModeDefault)&&(identical(other.microphoneEnabled, microphoneEnabled) || other.microphoneEnabled == microphoneEnabled)&&(identical(other.arEnabled, arEnabled) || other.arEnabled == arEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,nickname,ageBand,languageCode,bedtimeModeDefault,microphoneEnabled,arEnabled);

@override
String toString() {
  return 'ChildProfile(id: $id, userId: $userId, nickname: $nickname, ageBand: $ageBand, languageCode: $languageCode, bedtimeModeDefault: $bedtimeModeDefault, microphoneEnabled: $microphoneEnabled, arEnabled: $arEnabled)';
}


}

/// @nodoc
abstract mixin class $ChildProfileCopyWith<$Res>  {
  factory $ChildProfileCopyWith(ChildProfile value, $Res Function(ChildProfile) _then) = _$ChildProfileCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String? nickname, AgeBand ageBand, String languageCode, bool bedtimeModeDefault, bool microphoneEnabled, bool arEnabled
});




}
/// @nodoc
class _$ChildProfileCopyWithImpl<$Res>
    implements $ChildProfileCopyWith<$Res> {
  _$ChildProfileCopyWithImpl(this._self, this._then);

  final ChildProfile _self;
  final $Res Function(ChildProfile) _then;

/// Create a copy of ChildProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? nickname = freezed,Object? ageBand = null,Object? languageCode = null,Object? bedtimeModeDefault = null,Object? microphoneEnabled = null,Object? arEnabled = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,nickname: freezed == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String?,ageBand: null == ageBand ? _self.ageBand : ageBand // ignore: cast_nullable_to_non_nullable
as AgeBand,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,bedtimeModeDefault: null == bedtimeModeDefault ? _self.bedtimeModeDefault : bedtimeModeDefault // ignore: cast_nullable_to_non_nullable
as bool,microphoneEnabled: null == microphoneEnabled ? _self.microphoneEnabled : microphoneEnabled // ignore: cast_nullable_to_non_nullable
as bool,arEnabled: null == arEnabled ? _self.arEnabled : arEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ChildProfile].
extension ChildProfilePatterns on ChildProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChildProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChildProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChildProfile value)  $default,){
final _that = this;
switch (_that) {
case _ChildProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChildProfile value)?  $default,){
final _that = this;
switch (_that) {
case _ChildProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String? nickname,  AgeBand ageBand,  String languageCode,  bool bedtimeModeDefault,  bool microphoneEnabled,  bool arEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChildProfile() when $default != null:
return $default(_that.id,_that.userId,_that.nickname,_that.ageBand,_that.languageCode,_that.bedtimeModeDefault,_that.microphoneEnabled,_that.arEnabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String? nickname,  AgeBand ageBand,  String languageCode,  bool bedtimeModeDefault,  bool microphoneEnabled,  bool arEnabled)  $default,) {final _that = this;
switch (_that) {
case _ChildProfile():
return $default(_that.id,_that.userId,_that.nickname,_that.ageBand,_that.languageCode,_that.bedtimeModeDefault,_that.microphoneEnabled,_that.arEnabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String? nickname,  AgeBand ageBand,  String languageCode,  bool bedtimeModeDefault,  bool microphoneEnabled,  bool arEnabled)?  $default,) {final _that = this;
switch (_that) {
case _ChildProfile() when $default != null:
return $default(_that.id,_that.userId,_that.nickname,_that.ageBand,_that.languageCode,_that.bedtimeModeDefault,_that.microphoneEnabled,_that.arEnabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChildProfile implements ChildProfile {
  const _ChildProfile({required this.id, this.userId = 'local-parent', this.nickname, required this.ageBand, this.languageCode = 'en', this.bedtimeModeDefault = false, this.microphoneEnabled = false, this.arEnabled = true});
  factory _ChildProfile.fromJson(Map<String, dynamic> json) => _$ChildProfileFromJson(json);

@override final  String id;
/// FK → `users.id`. Single implicit local parent in this offline slice.
@override@JsonKey() final  String userId;
@override final  String? nickname;
@override final  AgeBand ageBand;
@override@JsonKey() final  String languageCode;
@override@JsonKey() final  bool bedtimeModeDefault;
@override@JsonKey() final  bool microphoneEnabled;
@override@JsonKey() final  bool arEnabled;

/// Create a copy of ChildProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChildProfileCopyWith<_ChildProfile> get copyWith => __$ChildProfileCopyWithImpl<_ChildProfile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChildProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChildProfile&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.ageBand, ageBand) || other.ageBand == ageBand)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.bedtimeModeDefault, bedtimeModeDefault) || other.bedtimeModeDefault == bedtimeModeDefault)&&(identical(other.microphoneEnabled, microphoneEnabled) || other.microphoneEnabled == microphoneEnabled)&&(identical(other.arEnabled, arEnabled) || other.arEnabled == arEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,nickname,ageBand,languageCode,bedtimeModeDefault,microphoneEnabled,arEnabled);

@override
String toString() {
  return 'ChildProfile(id: $id, userId: $userId, nickname: $nickname, ageBand: $ageBand, languageCode: $languageCode, bedtimeModeDefault: $bedtimeModeDefault, microphoneEnabled: $microphoneEnabled, arEnabled: $arEnabled)';
}


}

/// @nodoc
abstract mixin class _$ChildProfileCopyWith<$Res> implements $ChildProfileCopyWith<$Res> {
  factory _$ChildProfileCopyWith(_ChildProfile value, $Res Function(_ChildProfile) _then) = __$ChildProfileCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String? nickname, AgeBand ageBand, String languageCode, bool bedtimeModeDefault, bool microphoneEnabled, bool arEnabled
});




}
/// @nodoc
class __$ChildProfileCopyWithImpl<$Res>
    implements _$ChildProfileCopyWith<$Res> {
  __$ChildProfileCopyWithImpl(this._self, this._then);

  final _ChildProfile _self;
  final $Res Function(_ChildProfile) _then;

/// Create a copy of ChildProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? nickname = freezed,Object? ageBand = null,Object? languageCode = null,Object? bedtimeModeDefault = null,Object? microphoneEnabled = null,Object? arEnabled = null,}) {
  return _then(_ChildProfile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,nickname: freezed == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String?,ageBand: null == ageBand ? _self.ageBand : ageBand // ignore: cast_nullable_to_non_nullable
as AgeBand,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,bedtimeModeDefault: null == bedtimeModeDefault ? _self.bedtimeModeDefault : bedtimeModeDefault // ignore: cast_nullable_to_non_nullable
as bool,microphoneEnabled: null == microphoneEnabled ? _self.microphoneEnabled : microphoneEnabled // ignore: cast_nullable_to_non_nullable
as bool,arEnabled: null == arEnabled ? _self.arEnabled : arEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
