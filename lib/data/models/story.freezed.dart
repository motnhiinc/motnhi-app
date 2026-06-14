// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'story.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Story {

 String get id; String get title; String get slug; String? get description;/// Age range (§10 `age_min`/`age_max`).
 int get ageMin; int get ageMax; String get languageCode; int get durationSeconds;/// Library cover image (bundled asset path in this slice; CDN URL later).
 String? get coverAssetId; ContentStatus get contentStatus; String? get rightsOwnerId;/// Theme tags for browsing (§7.1.1).
 List<StoryTheme> get themes;/// Client/runtime flags (§11.1). Local impl unlocks all demo content;
/// premium/publisher-code stories stay locked until entitled (§5.7).
 bool get isDownloaded; bool get isUnlocked;
/// Create a copy of Story
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoryCopyWith<Story> get copyWith => _$StoryCopyWithImpl<Story>(this as Story, _$identity);

  /// Serializes this Story to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Story&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.description, description) || other.description == description)&&(identical(other.ageMin, ageMin) || other.ageMin == ageMin)&&(identical(other.ageMax, ageMax) || other.ageMax == ageMax)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.coverAssetId, coverAssetId) || other.coverAssetId == coverAssetId)&&(identical(other.contentStatus, contentStatus) || other.contentStatus == contentStatus)&&(identical(other.rightsOwnerId, rightsOwnerId) || other.rightsOwnerId == rightsOwnerId)&&const DeepCollectionEquality().equals(other.themes, themes)&&(identical(other.isDownloaded, isDownloaded) || other.isDownloaded == isDownloaded)&&(identical(other.isUnlocked, isUnlocked) || other.isUnlocked == isUnlocked));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,slug,description,ageMin,ageMax,languageCode,durationSeconds,coverAssetId,contentStatus,rightsOwnerId,const DeepCollectionEquality().hash(themes),isDownloaded,isUnlocked);

@override
String toString() {
  return 'Story(id: $id, title: $title, slug: $slug, description: $description, ageMin: $ageMin, ageMax: $ageMax, languageCode: $languageCode, durationSeconds: $durationSeconds, coverAssetId: $coverAssetId, contentStatus: $contentStatus, rightsOwnerId: $rightsOwnerId, themes: $themes, isDownloaded: $isDownloaded, isUnlocked: $isUnlocked)';
}


}

/// @nodoc
abstract mixin class $StoryCopyWith<$Res>  {
  factory $StoryCopyWith(Story value, $Res Function(Story) _then) = _$StoryCopyWithImpl;
@useResult
$Res call({
 String id, String title, String slug, String? description, int ageMin, int ageMax, String languageCode, int durationSeconds, String? coverAssetId, ContentStatus contentStatus, String? rightsOwnerId, List<StoryTheme> themes, bool isDownloaded, bool isUnlocked
});




}
/// @nodoc
class _$StoryCopyWithImpl<$Res>
    implements $StoryCopyWith<$Res> {
  _$StoryCopyWithImpl(this._self, this._then);

  final Story _self;
  final $Res Function(Story) _then;

/// Create a copy of Story
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? slug = null,Object? description = freezed,Object? ageMin = null,Object? ageMax = null,Object? languageCode = null,Object? durationSeconds = null,Object? coverAssetId = freezed,Object? contentStatus = null,Object? rightsOwnerId = freezed,Object? themes = null,Object? isDownloaded = null,Object? isUnlocked = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,ageMin: null == ageMin ? _self.ageMin : ageMin // ignore: cast_nullable_to_non_nullable
as int,ageMax: null == ageMax ? _self.ageMax : ageMax // ignore: cast_nullable_to_non_nullable
as int,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,durationSeconds: null == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int,coverAssetId: freezed == coverAssetId ? _self.coverAssetId : coverAssetId // ignore: cast_nullable_to_non_nullable
as String?,contentStatus: null == contentStatus ? _self.contentStatus : contentStatus // ignore: cast_nullable_to_non_nullable
as ContentStatus,rightsOwnerId: freezed == rightsOwnerId ? _self.rightsOwnerId : rightsOwnerId // ignore: cast_nullable_to_non_nullable
as String?,themes: null == themes ? _self.themes : themes // ignore: cast_nullable_to_non_nullable
as List<StoryTheme>,isDownloaded: null == isDownloaded ? _self.isDownloaded : isDownloaded // ignore: cast_nullable_to_non_nullable
as bool,isUnlocked: null == isUnlocked ? _self.isUnlocked : isUnlocked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Story].
extension StoryPatterns on Story {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Story value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Story() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Story value)  $default,){
final _that = this;
switch (_that) {
case _Story():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Story value)?  $default,){
final _that = this;
switch (_that) {
case _Story() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String slug,  String? description,  int ageMin,  int ageMax,  String languageCode,  int durationSeconds,  String? coverAssetId,  ContentStatus contentStatus,  String? rightsOwnerId,  List<StoryTheme> themes,  bool isDownloaded,  bool isUnlocked)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Story() when $default != null:
return $default(_that.id,_that.title,_that.slug,_that.description,_that.ageMin,_that.ageMax,_that.languageCode,_that.durationSeconds,_that.coverAssetId,_that.contentStatus,_that.rightsOwnerId,_that.themes,_that.isDownloaded,_that.isUnlocked);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String slug,  String? description,  int ageMin,  int ageMax,  String languageCode,  int durationSeconds,  String? coverAssetId,  ContentStatus contentStatus,  String? rightsOwnerId,  List<StoryTheme> themes,  bool isDownloaded,  bool isUnlocked)  $default,) {final _that = this;
switch (_that) {
case _Story():
return $default(_that.id,_that.title,_that.slug,_that.description,_that.ageMin,_that.ageMax,_that.languageCode,_that.durationSeconds,_that.coverAssetId,_that.contentStatus,_that.rightsOwnerId,_that.themes,_that.isDownloaded,_that.isUnlocked);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String slug,  String? description,  int ageMin,  int ageMax,  String languageCode,  int durationSeconds,  String? coverAssetId,  ContentStatus contentStatus,  String? rightsOwnerId,  List<StoryTheme> themes,  bool isDownloaded,  bool isUnlocked)?  $default,) {final _that = this;
switch (_that) {
case _Story() when $default != null:
return $default(_that.id,_that.title,_that.slug,_that.description,_that.ageMin,_that.ageMax,_that.languageCode,_that.durationSeconds,_that.coverAssetId,_that.contentStatus,_that.rightsOwnerId,_that.themes,_that.isDownloaded,_that.isUnlocked);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Story extends Story {
  const _Story({required this.id, required this.title, required this.slug, this.description, this.ageMin = 3, this.ageMax = 8, this.languageCode = 'en', this.durationSeconds = 0, this.coverAssetId, this.contentStatus = ContentStatus.published, this.rightsOwnerId, final  List<StoryTheme> themes = const <StoryTheme>[], this.isDownloaded = false, this.isUnlocked = true}): _themes = themes,super._();
  factory _Story.fromJson(Map<String, dynamic> json) => _$StoryFromJson(json);

@override final  String id;
@override final  String title;
@override final  String slug;
@override final  String? description;
/// Age range (§10 `age_min`/`age_max`).
@override@JsonKey() final  int ageMin;
@override@JsonKey() final  int ageMax;
@override@JsonKey() final  String languageCode;
@override@JsonKey() final  int durationSeconds;
/// Library cover image (bundled asset path in this slice; CDN URL later).
@override final  String? coverAssetId;
@override@JsonKey() final  ContentStatus contentStatus;
@override final  String? rightsOwnerId;
/// Theme tags for browsing (§7.1.1).
 final  List<StoryTheme> _themes;
/// Theme tags for browsing (§7.1.1).
@override@JsonKey() List<StoryTheme> get themes {
  if (_themes is EqualUnmodifiableListView) return _themes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_themes);
}

/// Client/runtime flags (§11.1). Local impl unlocks all demo content;
/// premium/publisher-code stories stay locked until entitled (§5.7).
@override@JsonKey() final  bool isDownloaded;
@override@JsonKey() final  bool isUnlocked;

/// Create a copy of Story
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoryCopyWith<_Story> get copyWith => __$StoryCopyWithImpl<_Story>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Story&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.description, description) || other.description == description)&&(identical(other.ageMin, ageMin) || other.ageMin == ageMin)&&(identical(other.ageMax, ageMax) || other.ageMax == ageMax)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.coverAssetId, coverAssetId) || other.coverAssetId == coverAssetId)&&(identical(other.contentStatus, contentStatus) || other.contentStatus == contentStatus)&&(identical(other.rightsOwnerId, rightsOwnerId) || other.rightsOwnerId == rightsOwnerId)&&const DeepCollectionEquality().equals(other._themes, _themes)&&(identical(other.isDownloaded, isDownloaded) || other.isDownloaded == isDownloaded)&&(identical(other.isUnlocked, isUnlocked) || other.isUnlocked == isUnlocked));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,slug,description,ageMin,ageMax,languageCode,durationSeconds,coverAssetId,contentStatus,rightsOwnerId,const DeepCollectionEquality().hash(_themes),isDownloaded,isUnlocked);

@override
String toString() {
  return 'Story(id: $id, title: $title, slug: $slug, description: $description, ageMin: $ageMin, ageMax: $ageMax, languageCode: $languageCode, durationSeconds: $durationSeconds, coverAssetId: $coverAssetId, contentStatus: $contentStatus, rightsOwnerId: $rightsOwnerId, themes: $themes, isDownloaded: $isDownloaded, isUnlocked: $isUnlocked)';
}


}

/// @nodoc
abstract mixin class _$StoryCopyWith<$Res> implements $StoryCopyWith<$Res> {
  factory _$StoryCopyWith(_Story value, $Res Function(_Story) _then) = __$StoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String slug, String? description, int ageMin, int ageMax, String languageCode, int durationSeconds, String? coverAssetId, ContentStatus contentStatus, String? rightsOwnerId, List<StoryTheme> themes, bool isDownloaded, bool isUnlocked
});




}
/// @nodoc
class __$StoryCopyWithImpl<$Res>
    implements _$StoryCopyWith<$Res> {
  __$StoryCopyWithImpl(this._self, this._then);

  final _Story _self;
  final $Res Function(_Story) _then;

/// Create a copy of Story
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? slug = null,Object? description = freezed,Object? ageMin = null,Object? ageMax = null,Object? languageCode = null,Object? durationSeconds = null,Object? coverAssetId = freezed,Object? contentStatus = null,Object? rightsOwnerId = freezed,Object? themes = null,Object? isDownloaded = null,Object? isUnlocked = null,}) {
  return _then(_Story(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,ageMin: null == ageMin ? _self.ageMin : ageMin // ignore: cast_nullable_to_non_nullable
as int,ageMax: null == ageMax ? _self.ageMax : ageMax // ignore: cast_nullable_to_non_nullable
as int,languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,durationSeconds: null == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int,coverAssetId: freezed == coverAssetId ? _self.coverAssetId : coverAssetId // ignore: cast_nullable_to_non_nullable
as String?,contentStatus: null == contentStatus ? _self.contentStatus : contentStatus // ignore: cast_nullable_to_non_nullable
as ContentStatus,rightsOwnerId: freezed == rightsOwnerId ? _self.rightsOwnerId : rightsOwnerId // ignore: cast_nullable_to_non_nullable
as String?,themes: null == themes ? _self._themes : themes // ignore: cast_nullable_to_non_nullable
as List<StoryTheme>,isDownloaded: null == isDownloaded ? _self.isDownloaded : isDownloaded // ignore: cast_nullable_to_non_nullable
as bool,isUnlocked: null == isUnlocked ? _self.isUnlocked : isUnlocked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
