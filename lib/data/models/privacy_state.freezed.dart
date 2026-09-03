// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'privacy_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PrivacyDataCounts {

 int get childProfiles; int get authoredStories; int get storySessions; int get interactionEvents;
/// Create a copy of PrivacyDataCounts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PrivacyDataCountsCopyWith<PrivacyDataCounts> get copyWith => _$PrivacyDataCountsCopyWithImpl<PrivacyDataCounts>(this as PrivacyDataCounts, _$identity);

  /// Serializes this PrivacyDataCounts to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PrivacyDataCounts&&(identical(other.childProfiles, childProfiles) || other.childProfiles == childProfiles)&&(identical(other.authoredStories, authoredStories) || other.authoredStories == authoredStories)&&(identical(other.storySessions, storySessions) || other.storySessions == storySessions)&&(identical(other.interactionEvents, interactionEvents) || other.interactionEvents == interactionEvents));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,childProfiles,authoredStories,storySessions,interactionEvents);

@override
String toString() {
  return 'PrivacyDataCounts(childProfiles: $childProfiles, authoredStories: $authoredStories, storySessions: $storySessions, interactionEvents: $interactionEvents)';
}


}

/// @nodoc
abstract mixin class $PrivacyDataCountsCopyWith<$Res>  {
  factory $PrivacyDataCountsCopyWith(PrivacyDataCounts value, $Res Function(PrivacyDataCounts) _then) = _$PrivacyDataCountsCopyWithImpl;
@useResult
$Res call({
 int childProfiles, int authoredStories, int storySessions, int interactionEvents
});




}
/// @nodoc
class _$PrivacyDataCountsCopyWithImpl<$Res>
    implements $PrivacyDataCountsCopyWith<$Res> {
  _$PrivacyDataCountsCopyWithImpl(this._self, this._then);

  final PrivacyDataCounts _self;
  final $Res Function(PrivacyDataCounts) _then;

/// Create a copy of PrivacyDataCounts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? childProfiles = null,Object? authoredStories = null,Object? storySessions = null,Object? interactionEvents = null,}) {
  return _then(_self.copyWith(
childProfiles: null == childProfiles ? _self.childProfiles : childProfiles // ignore: cast_nullable_to_non_nullable
as int,authoredStories: null == authoredStories ? _self.authoredStories : authoredStories // ignore: cast_nullable_to_non_nullable
as int,storySessions: null == storySessions ? _self.storySessions : storySessions // ignore: cast_nullable_to_non_nullable
as int,interactionEvents: null == interactionEvents ? _self.interactionEvents : interactionEvents // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PrivacyDataCounts].
extension PrivacyDataCountsPatterns on PrivacyDataCounts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PrivacyDataCounts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PrivacyDataCounts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PrivacyDataCounts value)  $default,){
final _that = this;
switch (_that) {
case _PrivacyDataCounts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PrivacyDataCounts value)?  $default,){
final _that = this;
switch (_that) {
case _PrivacyDataCounts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int childProfiles,  int authoredStories,  int storySessions,  int interactionEvents)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PrivacyDataCounts() when $default != null:
return $default(_that.childProfiles,_that.authoredStories,_that.storySessions,_that.interactionEvents);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int childProfiles,  int authoredStories,  int storySessions,  int interactionEvents)  $default,) {final _that = this;
switch (_that) {
case _PrivacyDataCounts():
return $default(_that.childProfiles,_that.authoredStories,_that.storySessions,_that.interactionEvents);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int childProfiles,  int authoredStories,  int storySessions,  int interactionEvents)?  $default,) {final _that = this;
switch (_that) {
case _PrivacyDataCounts() when $default != null:
return $default(_that.childProfiles,_that.authoredStories,_that.storySessions,_that.interactionEvents);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PrivacyDataCounts implements PrivacyDataCounts {
  const _PrivacyDataCounts({this.childProfiles = 0, this.authoredStories = 0, this.storySessions = 0, this.interactionEvents = 0});
  factory _PrivacyDataCounts.fromJson(Map<String, dynamic> json) => _$PrivacyDataCountsFromJson(json);

@override@JsonKey() final  int childProfiles;
@override@JsonKey() final  int authoredStories;
@override@JsonKey() final  int storySessions;
@override@JsonKey() final  int interactionEvents;

/// Create a copy of PrivacyDataCounts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PrivacyDataCountsCopyWith<_PrivacyDataCounts> get copyWith => __$PrivacyDataCountsCopyWithImpl<_PrivacyDataCounts>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PrivacyDataCountsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PrivacyDataCounts&&(identical(other.childProfiles, childProfiles) || other.childProfiles == childProfiles)&&(identical(other.authoredStories, authoredStories) || other.authoredStories == authoredStories)&&(identical(other.storySessions, storySessions) || other.storySessions == storySessions)&&(identical(other.interactionEvents, interactionEvents) || other.interactionEvents == interactionEvents));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,childProfiles,authoredStories,storySessions,interactionEvents);

@override
String toString() {
  return 'PrivacyDataCounts(childProfiles: $childProfiles, authoredStories: $authoredStories, storySessions: $storySessions, interactionEvents: $interactionEvents)';
}


}

/// @nodoc
abstract mixin class _$PrivacyDataCountsCopyWith<$Res> implements $PrivacyDataCountsCopyWith<$Res> {
  factory _$PrivacyDataCountsCopyWith(_PrivacyDataCounts value, $Res Function(_PrivacyDataCounts) _then) = __$PrivacyDataCountsCopyWithImpl;
@override @useResult
$Res call({
 int childProfiles, int authoredStories, int storySessions, int interactionEvents
});




}
/// @nodoc
class __$PrivacyDataCountsCopyWithImpl<$Res>
    implements _$PrivacyDataCountsCopyWith<$Res> {
  __$PrivacyDataCountsCopyWithImpl(this._self, this._then);

  final _PrivacyDataCounts _self;
  final $Res Function(_PrivacyDataCounts) _then;

/// Create a copy of PrivacyDataCounts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? childProfiles = null,Object? authoredStories = null,Object? storySessions = null,Object? interactionEvents = null,}) {
  return _then(_PrivacyDataCounts(
childProfiles: null == childProfiles ? _self.childProfiles : childProfiles // ignore: cast_nullable_to_non_nullable
as int,authoredStories: null == authoredStories ? _self.authoredStories : authoredStories // ignore: cast_nullable_to_non_nullable
as int,storySessions: null == storySessions ? _self.storySessions : storySessions // ignore: cast_nullable_to_non_nullable
as int,interactionEvents: null == interactionEvents ? _self.interactionEvents : interactionEvents // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PrivacyState {

 String get currentPolicyVersion; String? get acceptedPolicyVersion; bool get reviewRequired; DateTime? get coreStorageAcceptedAt; bool get progressTrackingEnabled; bool get cloudTtsEnabled; bool get effectiveProgressTrackingEnabled; bool get effectiveCloudTtsEnabled; DateTime get lastActiveAt; DateTime get updatedAt; PrivacyDataCounts get counts;
/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PrivacyStateCopyWith<PrivacyState> get copyWith => _$PrivacyStateCopyWithImpl<PrivacyState>(this as PrivacyState, _$identity);

  /// Serializes this PrivacyState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PrivacyState&&(identical(other.currentPolicyVersion, currentPolicyVersion) || other.currentPolicyVersion == currentPolicyVersion)&&(identical(other.acceptedPolicyVersion, acceptedPolicyVersion) || other.acceptedPolicyVersion == acceptedPolicyVersion)&&(identical(other.reviewRequired, reviewRequired) || other.reviewRequired == reviewRequired)&&(identical(other.coreStorageAcceptedAt, coreStorageAcceptedAt) || other.coreStorageAcceptedAt == coreStorageAcceptedAt)&&(identical(other.progressTrackingEnabled, progressTrackingEnabled) || other.progressTrackingEnabled == progressTrackingEnabled)&&(identical(other.cloudTtsEnabled, cloudTtsEnabled) || other.cloudTtsEnabled == cloudTtsEnabled)&&(identical(other.effectiveProgressTrackingEnabled, effectiveProgressTrackingEnabled) || other.effectiveProgressTrackingEnabled == effectiveProgressTrackingEnabled)&&(identical(other.effectiveCloudTtsEnabled, effectiveCloudTtsEnabled) || other.effectiveCloudTtsEnabled == effectiveCloudTtsEnabled)&&(identical(other.lastActiveAt, lastActiveAt) || other.lastActiveAt == lastActiveAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.counts, counts) || other.counts == counts));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,currentPolicyVersion,acceptedPolicyVersion,reviewRequired,coreStorageAcceptedAt,progressTrackingEnabled,cloudTtsEnabled,effectiveProgressTrackingEnabled,effectiveCloudTtsEnabled,lastActiveAt,updatedAt,counts);

@override
String toString() {
  return 'PrivacyState(currentPolicyVersion: $currentPolicyVersion, acceptedPolicyVersion: $acceptedPolicyVersion, reviewRequired: $reviewRequired, coreStorageAcceptedAt: $coreStorageAcceptedAt, progressTrackingEnabled: $progressTrackingEnabled, cloudTtsEnabled: $cloudTtsEnabled, effectiveProgressTrackingEnabled: $effectiveProgressTrackingEnabled, effectiveCloudTtsEnabled: $effectiveCloudTtsEnabled, lastActiveAt: $lastActiveAt, updatedAt: $updatedAt, counts: $counts)';
}


}

/// @nodoc
abstract mixin class $PrivacyStateCopyWith<$Res>  {
  factory $PrivacyStateCopyWith(PrivacyState value, $Res Function(PrivacyState) _then) = _$PrivacyStateCopyWithImpl;
@useResult
$Res call({
 String currentPolicyVersion, String? acceptedPolicyVersion, bool reviewRequired, DateTime? coreStorageAcceptedAt, bool progressTrackingEnabled, bool cloudTtsEnabled, bool effectiveProgressTrackingEnabled, bool effectiveCloudTtsEnabled, DateTime lastActiveAt, DateTime updatedAt, PrivacyDataCounts counts
});


$PrivacyDataCountsCopyWith<$Res> get counts;

}
/// @nodoc
class _$PrivacyStateCopyWithImpl<$Res>
    implements $PrivacyStateCopyWith<$Res> {
  _$PrivacyStateCopyWithImpl(this._self, this._then);

  final PrivacyState _self;
  final $Res Function(PrivacyState) _then;

/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currentPolicyVersion = null,Object? acceptedPolicyVersion = freezed,Object? reviewRequired = null,Object? coreStorageAcceptedAt = freezed,Object? progressTrackingEnabled = null,Object? cloudTtsEnabled = null,Object? effectiveProgressTrackingEnabled = null,Object? effectiveCloudTtsEnabled = null,Object? lastActiveAt = null,Object? updatedAt = null,Object? counts = null,}) {
  return _then(_self.copyWith(
currentPolicyVersion: null == currentPolicyVersion ? _self.currentPolicyVersion : currentPolicyVersion // ignore: cast_nullable_to_non_nullable
as String,acceptedPolicyVersion: freezed == acceptedPolicyVersion ? _self.acceptedPolicyVersion : acceptedPolicyVersion // ignore: cast_nullable_to_non_nullable
as String?,reviewRequired: null == reviewRequired ? _self.reviewRequired : reviewRequired // ignore: cast_nullable_to_non_nullable
as bool,coreStorageAcceptedAt: freezed == coreStorageAcceptedAt ? _self.coreStorageAcceptedAt : coreStorageAcceptedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,progressTrackingEnabled: null == progressTrackingEnabled ? _self.progressTrackingEnabled : progressTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,cloudTtsEnabled: null == cloudTtsEnabled ? _self.cloudTtsEnabled : cloudTtsEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveProgressTrackingEnabled: null == effectiveProgressTrackingEnabled ? _self.effectiveProgressTrackingEnabled : effectiveProgressTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveCloudTtsEnabled: null == effectiveCloudTtsEnabled ? _self.effectiveCloudTtsEnabled : effectiveCloudTtsEnabled // ignore: cast_nullable_to_non_nullable
as bool,lastActiveAt: null == lastActiveAt ? _self.lastActiveAt : lastActiveAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,counts: null == counts ? _self.counts : counts // ignore: cast_nullable_to_non_nullable
as PrivacyDataCounts,
  ));
}
/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PrivacyDataCountsCopyWith<$Res> get counts {
  
  return $PrivacyDataCountsCopyWith<$Res>(_self.counts, (value) {
    return _then(_self.copyWith(counts: value));
  });
}
}


/// Adds pattern-matching-related methods to [PrivacyState].
extension PrivacyStatePatterns on PrivacyState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PrivacyState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PrivacyState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PrivacyState value)  $default,){
final _that = this;
switch (_that) {
case _PrivacyState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PrivacyState value)?  $default,){
final _that = this;
switch (_that) {
case _PrivacyState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String currentPolicyVersion,  String? acceptedPolicyVersion,  bool reviewRequired,  DateTime? coreStorageAcceptedAt,  bool progressTrackingEnabled,  bool cloudTtsEnabled,  bool effectiveProgressTrackingEnabled,  bool effectiveCloudTtsEnabled,  DateTime lastActiveAt,  DateTime updatedAt,  PrivacyDataCounts counts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PrivacyState() when $default != null:
return $default(_that.currentPolicyVersion,_that.acceptedPolicyVersion,_that.reviewRequired,_that.coreStorageAcceptedAt,_that.progressTrackingEnabled,_that.cloudTtsEnabled,_that.effectiveProgressTrackingEnabled,_that.effectiveCloudTtsEnabled,_that.lastActiveAt,_that.updatedAt,_that.counts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String currentPolicyVersion,  String? acceptedPolicyVersion,  bool reviewRequired,  DateTime? coreStorageAcceptedAt,  bool progressTrackingEnabled,  bool cloudTtsEnabled,  bool effectiveProgressTrackingEnabled,  bool effectiveCloudTtsEnabled,  DateTime lastActiveAt,  DateTime updatedAt,  PrivacyDataCounts counts)  $default,) {final _that = this;
switch (_that) {
case _PrivacyState():
return $default(_that.currentPolicyVersion,_that.acceptedPolicyVersion,_that.reviewRequired,_that.coreStorageAcceptedAt,_that.progressTrackingEnabled,_that.cloudTtsEnabled,_that.effectiveProgressTrackingEnabled,_that.effectiveCloudTtsEnabled,_that.lastActiveAt,_that.updatedAt,_that.counts);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String currentPolicyVersion,  String? acceptedPolicyVersion,  bool reviewRequired,  DateTime? coreStorageAcceptedAt,  bool progressTrackingEnabled,  bool cloudTtsEnabled,  bool effectiveProgressTrackingEnabled,  bool effectiveCloudTtsEnabled,  DateTime lastActiveAt,  DateTime updatedAt,  PrivacyDataCounts counts)?  $default,) {final _that = this;
switch (_that) {
case _PrivacyState() when $default != null:
return $default(_that.currentPolicyVersion,_that.acceptedPolicyVersion,_that.reviewRequired,_that.coreStorageAcceptedAt,_that.progressTrackingEnabled,_that.cloudTtsEnabled,_that.effectiveProgressTrackingEnabled,_that.effectiveCloudTtsEnabled,_that.lastActiveAt,_that.updatedAt,_that.counts);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PrivacyState implements PrivacyState {
  const _PrivacyState({required this.currentPolicyVersion, this.acceptedPolicyVersion, required this.reviewRequired, this.coreStorageAcceptedAt, this.progressTrackingEnabled = false, this.cloudTtsEnabled = false, this.effectiveProgressTrackingEnabled = false, this.effectiveCloudTtsEnabled = false, required this.lastActiveAt, required this.updatedAt, this.counts = const PrivacyDataCounts()});
  factory _PrivacyState.fromJson(Map<String, dynamic> json) => _$PrivacyStateFromJson(json);

@override final  String currentPolicyVersion;
@override final  String? acceptedPolicyVersion;
@override final  bool reviewRequired;
@override final  DateTime? coreStorageAcceptedAt;
@override@JsonKey() final  bool progressTrackingEnabled;
@override@JsonKey() final  bool cloudTtsEnabled;
@override@JsonKey() final  bool effectiveProgressTrackingEnabled;
@override@JsonKey() final  bool effectiveCloudTtsEnabled;
@override final  DateTime lastActiveAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  PrivacyDataCounts counts;

/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PrivacyStateCopyWith<_PrivacyState> get copyWith => __$PrivacyStateCopyWithImpl<_PrivacyState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PrivacyStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PrivacyState&&(identical(other.currentPolicyVersion, currentPolicyVersion) || other.currentPolicyVersion == currentPolicyVersion)&&(identical(other.acceptedPolicyVersion, acceptedPolicyVersion) || other.acceptedPolicyVersion == acceptedPolicyVersion)&&(identical(other.reviewRequired, reviewRequired) || other.reviewRequired == reviewRequired)&&(identical(other.coreStorageAcceptedAt, coreStorageAcceptedAt) || other.coreStorageAcceptedAt == coreStorageAcceptedAt)&&(identical(other.progressTrackingEnabled, progressTrackingEnabled) || other.progressTrackingEnabled == progressTrackingEnabled)&&(identical(other.cloudTtsEnabled, cloudTtsEnabled) || other.cloudTtsEnabled == cloudTtsEnabled)&&(identical(other.effectiveProgressTrackingEnabled, effectiveProgressTrackingEnabled) || other.effectiveProgressTrackingEnabled == effectiveProgressTrackingEnabled)&&(identical(other.effectiveCloudTtsEnabled, effectiveCloudTtsEnabled) || other.effectiveCloudTtsEnabled == effectiveCloudTtsEnabled)&&(identical(other.lastActiveAt, lastActiveAt) || other.lastActiveAt == lastActiveAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.counts, counts) || other.counts == counts));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,currentPolicyVersion,acceptedPolicyVersion,reviewRequired,coreStorageAcceptedAt,progressTrackingEnabled,cloudTtsEnabled,effectiveProgressTrackingEnabled,effectiveCloudTtsEnabled,lastActiveAt,updatedAt,counts);

@override
String toString() {
  return 'PrivacyState(currentPolicyVersion: $currentPolicyVersion, acceptedPolicyVersion: $acceptedPolicyVersion, reviewRequired: $reviewRequired, coreStorageAcceptedAt: $coreStorageAcceptedAt, progressTrackingEnabled: $progressTrackingEnabled, cloudTtsEnabled: $cloudTtsEnabled, effectiveProgressTrackingEnabled: $effectiveProgressTrackingEnabled, effectiveCloudTtsEnabled: $effectiveCloudTtsEnabled, lastActiveAt: $lastActiveAt, updatedAt: $updatedAt, counts: $counts)';
}


}

/// @nodoc
abstract mixin class _$PrivacyStateCopyWith<$Res> implements $PrivacyStateCopyWith<$Res> {
  factory _$PrivacyStateCopyWith(_PrivacyState value, $Res Function(_PrivacyState) _then) = __$PrivacyStateCopyWithImpl;
@override @useResult
$Res call({
 String currentPolicyVersion, String? acceptedPolicyVersion, bool reviewRequired, DateTime? coreStorageAcceptedAt, bool progressTrackingEnabled, bool cloudTtsEnabled, bool effectiveProgressTrackingEnabled, bool effectiveCloudTtsEnabled, DateTime lastActiveAt, DateTime updatedAt, PrivacyDataCounts counts
});


@override $PrivacyDataCountsCopyWith<$Res> get counts;

}
/// @nodoc
class __$PrivacyStateCopyWithImpl<$Res>
    implements _$PrivacyStateCopyWith<$Res> {
  __$PrivacyStateCopyWithImpl(this._self, this._then);

  final _PrivacyState _self;
  final $Res Function(_PrivacyState) _then;

/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currentPolicyVersion = null,Object? acceptedPolicyVersion = freezed,Object? reviewRequired = null,Object? coreStorageAcceptedAt = freezed,Object? progressTrackingEnabled = null,Object? cloudTtsEnabled = null,Object? effectiveProgressTrackingEnabled = null,Object? effectiveCloudTtsEnabled = null,Object? lastActiveAt = null,Object? updatedAt = null,Object? counts = null,}) {
  return _then(_PrivacyState(
currentPolicyVersion: null == currentPolicyVersion ? _self.currentPolicyVersion : currentPolicyVersion // ignore: cast_nullable_to_non_nullable
as String,acceptedPolicyVersion: freezed == acceptedPolicyVersion ? _self.acceptedPolicyVersion : acceptedPolicyVersion // ignore: cast_nullable_to_non_nullable
as String?,reviewRequired: null == reviewRequired ? _self.reviewRequired : reviewRequired // ignore: cast_nullable_to_non_nullable
as bool,coreStorageAcceptedAt: freezed == coreStorageAcceptedAt ? _self.coreStorageAcceptedAt : coreStorageAcceptedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,progressTrackingEnabled: null == progressTrackingEnabled ? _self.progressTrackingEnabled : progressTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,cloudTtsEnabled: null == cloudTtsEnabled ? _self.cloudTtsEnabled : cloudTtsEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveProgressTrackingEnabled: null == effectiveProgressTrackingEnabled ? _self.effectiveProgressTrackingEnabled : effectiveProgressTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveCloudTtsEnabled: null == effectiveCloudTtsEnabled ? _self.effectiveCloudTtsEnabled : effectiveCloudTtsEnabled // ignore: cast_nullable_to_non_nullable
as bool,lastActiveAt: null == lastActiveAt ? _self.lastActiveAt : lastActiveAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,counts: null == counts ? _self.counts : counts // ignore: cast_nullable_to_non_nullable
as PrivacyDataCounts,
  ));
}

/// Create a copy of PrivacyState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PrivacyDataCountsCopyWith<$Res> get counts {
  
  return $PrivacyDataCountsCopyWith<$Res>(_self.counts, (value) {
    return _then(_self.copyWith(counts: value));
  });
}
}

// dart format on
