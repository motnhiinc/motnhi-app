import '../models/models.dart';
import '../sources/local_content_source.dart';

/// Read access to the curated story library and story detail (§9.5.3).
/// Backs `GET /v1/stories` (§11.1) and `GET /v1/stories/{id}` (§11.2).
abstract class StoryRepository {
  /// Library list, optionally filtered by age band and language (§11.1).
  /// Only published + unlocked stories are surfaced to the child (§5.7).
  Future<List<Story>> getLibrary({AgeBand? ageBand, String? language});

  /// Full story payload, or null if unknown (§11.2).
  Future<StoryDetail?> getStory(String storyId);
}

/// Local implementation backed by bundled assets. In this offline slice all
/// demo content is treated as published + unlocked.
class LocalStoryRepository implements StoryRepository {
  LocalStoryRepository(this._source);

  final LocalContentSource _source;

  @override
  Future<List<Story>> getLibrary({AgeBand? ageBand, String? language}) async {
    final stories = await _source.loadLibrary();
    return stories
        .where((s) => s.contentStatus == ContentStatus.published)
        .where((s) => ageBand == null || s.matchesAgeBand(ageBand))
        .where((s) => language == null || s.languageCode == language)
        .toList();
  }

  @override
  Future<StoryDetail?> getStory(String storyId) => _source.loadStory(storyId);
}
