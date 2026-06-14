import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';

/// Full detail for a story (§11.2), keyed by story id.
final storyDetailProvider =
    FutureProvider.family<StoryDetail?, String>((ref, storyId) {
  return ref.watch(storyRepositoryProvider).getStory(storyId);
});
