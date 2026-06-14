import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/models.dart';

/// Loads bundled story content from `assets/data/`. Each story has a detail
/// file shaped exactly like `GET /v1/stories/{id}` (§11.2); `manifest.json`
/// lists them. This is the local stand-in for the Story Content Service
/// (§9.5.3) — swapping to a real HTTP source is a one-class change.
class LocalContentSource {
  LocalContentSource({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  List<StoryDetail>? _cache;

  /// Loads and caches every bundled story detail.
  Future<List<StoryDetail>> loadAll() async {
    if (_cache != null) return _cache!;

    final manifestRaw = await _bundle.loadString('assets/data/manifest.json');
    final manifest = json.decode(manifestRaw) as Map<String, dynamic>;
    final slugs = (manifest['stories'] as List<dynamic>).cast<String>();

    final details = <StoryDetail>[];
    for (final slug in slugs) {
      final raw = await _bundle.loadString('assets/data/$slug.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      details.add(StoryDetail.fromJson(map));
    }
    _cache = details;
    return details;
  }

  /// The library list (§11.1) derived from each story's detail.
  Future<List<Story>> loadLibrary() async {
    final all = await loadAll();
    return all.map((d) => d.story).toList();
  }

  /// Full detail for one story (§11.2), or null if not bundled.
  Future<StoryDetail?> loadStory(String storyId) async {
    final all = await loadAll();
    return all.where((d) => d.story.id == storyId).firstOrNull;
  }
}
