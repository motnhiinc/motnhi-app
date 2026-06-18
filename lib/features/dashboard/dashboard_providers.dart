import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../profile/profile_providers.dart';

/// Aggregated reading activity for the parent dashboard (§7.2.2, §16).
class DashboardSummary {
  const DashboardSummary({
    required this.storiesCompleted,
    required this.totalReadingTime,
    required this.questionsAnswered,
    required this.questionsCorrect,
    required this.recentStories,
    required this.recommended,
  });

  final int storiesCompleted;
  final Duration totalReadingTime;
  final int questionsAnswered;
  final int questionsCorrect;
  final List<Story> recentStories;
  final List<Story> recommended;

  double get questionAccuracy =>
      questionsAnswered == 0 ? 0 : questionsCorrect / questionsAnswered;
}

/// Builds the dashboard summary by joining sessions + events with the library.
/// Privacy-preserving: aggregates only, no per-event child profiling (§16.4).
final dashboardSummaryProvider =
    FutureProvider<DashboardSummary>((ref) async {
  final profile = ref.watch(childProfileProvider).value;
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final storyRepo = ref.watch(storyRepositoryProvider);

  final sessions =
      await sessionRepo.getSessions(childProfileId: profile?.id);
  final eventLists = await Future.wait(
    sessions.map((s) => sessionRepo.getEvents(sessionId: s.id)),
  );
  final events = eventLists.expand((list) => list).toList();
  final library = await storyRepo.getLibrary();
  final byId = {for (final s in library) s.id: s};

  final completed = sessions.where((s) => s.isCompleted).toList();
  final completedStoryIds = completed.map((s) => s.storyId).toSet();

  final totalTime = completed.fold<Duration>(
    Duration.zero,
    (acc, s) => acc + (s.readingTime ?? Duration.zero),
  );

  final answers =
      events.where((e) => e.eventType == 'question_answered').toList();
  final correct =
      answers.where((e) => e.payload['is_correct'] == true).length;

  // Recent: most-recently started stories (dedup, newest first).
  final recentIds = <String>[];
  for (final s in sessions.reversed) {
    if (!recentIds.contains(s.storyId) && byId.containsKey(s.storyId)) {
      recentIds.add(s.storyId);
    }
  }
  final recent =
      recentIds.take(5).map((id) => byId[id]!).toList();

  // Recommendation (§25 simple rules): age-appropriate stories not yet
  // completed, newest library order.
  final recommended = library
      .where((s) => !completedStoryIds.contains(s.id))
      .where((s) => profile == null || s.matchesAgeBand(profile.ageBand))
      .take(5)
      .toList();

  return DashboardSummary(
    storiesCompleted: completedStoryIds.length,
    totalReadingTime: totalTime,
    questionsAnswered: answers.length,
    questionsCorrect: correct,
    recentStories: recent,
    recommended: recommended,
  );
});
