import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../privacy/privacy_providers.dart';
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

/// Which privacy situation the dashboard renders (§14). History presence
/// separates the paired states: tracking off → no-history vs retained-history;
/// tracking on → empty vs active.
enum DashboardTrackingStatus {
  /// Progress tracking is off and no history exists — nothing was ever saved.
  trackingOffNoHistory,

  /// Progress tracking is on but the child has not read anything yet.
  trackingOnNoHistory,

  /// Progress tracking is on with readable history — live stats.
  trackingOnWithHistory,

  /// Progress tracking is off but previously saved (retained) history exists.
  trackingOffRetainedHistory,
}

/// Privacy-aware dashboard state: the aggregate [summary] plus the [status]
/// telling the screen how it may be presented.
class DashboardState {
  const DashboardState({required this.status, required this.summary});

  final DashboardTrackingStatus status;
  final DashboardSummary summary;
}

/// Builds the privacy-aware dashboard state by joining the effective privacy
/// consent with sessions + events and the library (§14, §16). Privacy
/// preserving: aggregates only, no per-event child profiling (§16.4).
///
/// A remote session-list failure surfaces as an error (retry UI) — never as an
/// empty history, which would be indistinguishable from a tracking-off fresh
/// start. Library recommendations stay available in every state.
final dashboardStateProvider = FutureProvider<DashboardState>((ref) async {
  final profile = ref.watch(childProfileProvider).value;
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final storyRepo = ref.watch(storyRepositoryProvider);
  final trackingEnabled = ref.watch(effectiveProgressTrackingProvider);

  final sessions = await sessionRepo.getSessions(childProfileId: profile?.id);
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
  final correct = answers.where((e) => e.payload['is_correct'] == true).length;

  // Recent: most-recently started stories (dedup, newest first).
  final recentIds = <String>[];
  for (final s in sessions.reversed) {
    if (!recentIds.contains(s.storyId) && byId.containsKey(s.storyId)) {
      recentIds.add(s.storyId);
    }
  }
  final recent = recentIds.take(5).map((id) => byId[id]!).toList();

  // Recommendation (§25 simple rules): age-appropriate stories not yet
  // completed, newest library order.
  final recommended = library
      .where((s) => !completedStoryIds.contains(s.id))
      .where((s) => profile == null || s.matchesAgeBand(profile.ageBand))
      .take(5)
      .toList();

  final hasHistory = sessions.isNotEmpty;
  final status = switch ((trackingEnabled, hasHistory)) {
    (false, false) => DashboardTrackingStatus.trackingOffNoHistory,
    (false, true) => DashboardTrackingStatus.trackingOffRetainedHistory,
    (true, false) => DashboardTrackingStatus.trackingOnNoHistory,
    (true, true) => DashboardTrackingStatus.trackingOnWithHistory,
  };

  return DashboardState(
    status: status,
    summary: DashboardSummary(
      storiesCompleted: completedStoryIds.length,
      totalReadingTime: totalTime,
      questionsAnswered: answers.length,
      questionsCorrect: correct,
      recentStories: recent,
      recommended: recommended,
    ),
  );
});

/// Aggregate-only view for screens that just need recents/recommendations
/// (child home, My Books). Derived from [dashboardStateProvider] so both share
/// one session/event fetch.
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  return (await ref.watch(dashboardStateProvider.future)).summary;
});
