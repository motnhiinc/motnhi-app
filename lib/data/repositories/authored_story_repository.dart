import '../../features/story_composer/story_draft.dart';
import '../models/models.dart';

/// Write access for user-authored stories (POST/DELETE /v1/stories).
///
/// Deliberately separate from [StoryRepository]: reads need no change at all,
/// because authored stories come back through GET /v1/stories like any other,
/// and widening that interface would force stub methods onto
/// [LocalStoryRepository], which nothing references.
abstract interface class AuthoredStoryRepository {
  /// Creates the story server-side and returns it as the library sees it.
  Future<Story> createStory(StoryDraft draft);

  /// Deletes an authored story. A 404 is treated as success — the story is
  /// gone either way.
  Future<void> deleteStory(String storyId);
}

/// Typed creation/deletion failure. [code] is the backend `detail` when the
/// server sent one — notably `privacy_policy_review_required`, which the
/// composer must surface distinctly — otherwise a client-side classification
/// (`quota_reached`, `invalid_story`, `rate_limited`, `timeout`,
/// `backend_unreachable`, `authentication`, `upstream_failed`).
final class AuthoredStoryFailure implements Exception {
  const AuthoredStoryFailure(this.code);

  final String code;

  @override
  String toString() => 'AuthoredStoryFailure($code)';
}
