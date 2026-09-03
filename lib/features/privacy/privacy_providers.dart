import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../../data/sources/persistence_keys.dart';
import '../profile/profile_providers.dart';

/// Fresh privacy & consent state from the server (§14). The single source of
/// authorization truth: access derivation and the effective toggles below read
/// this provider, never the display-only [privacyStateCacheProvider].
final privacyProvider =
    AsyncNotifierProvider<PrivacyNotifier, PrivacyState>(PrivacyNotifier.new);

/// Display-only mirror of the last server response, persisted after every
/// successful fetch/update so unavailable/retry UI has something to show while
/// the fresh request is failing. Must never drive access, consent, or the
/// effective toggles.
final privacyStateCacheProvider = Provider<PrivacyState?>((ref) {
  final json = ref.watch(keyValueStoreProvider).readJson(privacyStateCacheKey);
  if (json == null) return null;
  try {
    return PrivacyState.fromJson(json);
  } catch (_) {
    return null;
  }
});

class PrivacyNotifier extends AsyncNotifier<PrivacyState> {
  /// Serializes mutations: each awaits the previous in-flight one before it
  /// starts, so consent submissions never interleave on the server.
  Future<void> _mutationQueue = Future<void>.value();

  @override
  Future<PrivacyState> build() async {
    final fresh = await ref.watch(privacyRepositoryProvider).fetchPrivacy();
    await _writeCache(fresh);
    return fresh;
  }

  /// Submits consent/preference changes. Resolves only after the server
  /// response lands; [state] becomes [AsyncData] only from that response. On
  /// failure the last server response (captured in [previous]) stays available
  /// for retry UI — it is display state, never re-asserted as fresh
  /// authorization.
  Future<void> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
  }) {
    final task = _mutationQueue.then((_) async {
      // Previous server truth, kept separate from the mutation input so retry
      // UI can render it. Only a server response may set AsyncData.
      final previous = state.value;
      try {
        final fresh = await ref.read(privacyRepositoryProvider).updatePrivacy(
              policyVersion: policyVersion,
              coreStorageAccepted: coreStorageAccepted,
              progressTrackingEnabled: progressTrackingEnabled,
              cloudTtsEnabled: cloudTtsEnabled,
            );
        await _writeCache(fresh);
        state = AsyncData(fresh);
      } catch (error) {
        // Restore the last server response for retry UI and surface the
        // failure to the caller instead.
        if (previous != null) state = AsyncData(previous);
        rethrow;
      }
    });
    _mutationQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  /// Parent data control: updates the progress-tracking choice. Resends the
  /// complete current-policy body and resolves only after the server
  /// response lands (post-commit), so the UI opens any follow-up
  /// retain/delete dialog only after the server confirmed the change.
  Future<void> setProgressTracking(bool enabled) =>
      _updateCurrent(progressTrackingEnabled: enabled);

  /// Parent data control: updates the cloud-narration choice. Same contract
  /// as [setProgressTracking].
  Future<void> setCloudTts(bool enabled) =>
      _updateCurrent(cloudTtsEnabled: enabled);

  /// Deletes all reading history (sessions + interaction events) on the
  /// server, then refetches privacy state so the stored-data counts change.
  /// A failure keeps the last server response and rethrows.
  Future<void> deleteReadingHistory() {
    final task = _mutationQueue.then((_) async {
      final previous = state.value;
      try {
        await ref.read(privacyRepositoryProvider).deleteReadingHistory();
        final fresh = await ref.read(privacyRepositoryProvider).fetchPrivacy();
        await _writeCache(fresh);
        state = AsyncData(fresh);
      } catch (error) {
        if (previous != null) state = AsyncData(previous);
        rethrow;
      }
    });
    _mutationQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  /// Full child-data deletion (Task 20). The server deletion must commit
  /// first: a failed request rethrows and leaves every local key and file
  /// untouched. Only after confirmation does the local cleaner run —
  /// marker-first ordered removal of every child key (including
  /// [privacyActivityLastUtcDateKey]) and owned generated-audio file,
  /// followed by provider invalidation so access routing re-derives from the
  /// fresh null-policy server state.
  Future<void> deleteChildData() {
    final task = _mutationQueue.then((_) async {
      await ref.read(privacyRepositoryProvider).deleteChildData();
      await ref.read(childDataCleanerProvider).clean();
    });
    _mutationQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  /// Shared body for the parent option toggles: every PUT resends the
  /// complete current-policy body (policy version, required core-storage
  /// acceptance) plus the one changed choice, built from the latest server
  /// response at execution time. Queued on [_mutationQueue] so rapid toggles
  /// reach the server in order.
  Future<void> _updateCurrent({
    bool? progressTrackingEnabled,
    bool? cloudTtsEnabled,
  }) {
    final task = _mutationQueue.then((_) async {
      // Read at execution time, not call time, so a queued mutation always
      // builds its body from the previous mutation's server response.
      final current = state.value;
      if (current == null) {
        throw StateError(
          'Privacy state unavailable; cannot update privacy choices.',
        );
      }
      try {
        final fresh = await ref.read(privacyRepositoryProvider).updatePrivacy(
              policyVersion:
                  current.acceptedPolicyVersion ?? current.currentPolicyVersion,
              coreStorageAccepted: true,
              progressTrackingEnabled:
                  progressTrackingEnabled ?? current.progressTrackingEnabled,
              cloudTtsEnabled: cloudTtsEnabled ?? current.cloudTtsEnabled,
            );
        await _writeCache(fresh);
        state = AsyncData(fresh);
      } catch (error) {
        // Keep the last server response for retry UI and surface the failure.
        state = AsyncData(current);
        rethrow;
      }
    });
    _mutationQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  /// Best-effort: the display cache must never block or discard a server
  /// response the server already committed — a write failure is swallowed so
  /// build()/updatePrivacy() critical paths stay unaffected.
  Future<void> _writeCache(PrivacyState fresh) async {
    try {
      await ref
          .read(keyValueStoreProvider)
          .writeJson(privacyStateCacheKey, fresh.toJson());
    } catch (_) {
      // Display cache only; losing it just means stale/unavailable retry UI.
    }
  }
}

/// Effective progress-tracking consent (§14). Reads ONLY the fresh async
/// server result: false while loading, on error, or when absent.
final effectiveProgressTrackingProvider = Provider<bool>((ref) {
  return ref.watch(privacyProvider).value?.effectiveProgressTrackingEnabled ??
      false;
});

/// Effective cloud-narration consent (§14). Reads ONLY the fresh async server
/// result: false while loading, on error, or when absent.
final effectiveCloudTtsProvider = Provider<bool>((ref) {
  return ref.watch(privacyProvider).value?.effectiveCloudTtsEnabled ?? false;
});

/// Fail-closed app access derived from server privacy truth + profile state.
enum AppAccessStatus {
  loading,
  setupRequired,
  policyReviewRequired,
  ready,
  unavailable
}

class AppAccessState {
  const AppAccessState(this.status, {this.consentAlreadySubmitted = false});

  final AppAccessStatus status;

  /// True when consent already succeeded (current acceptance) and only the
  /// profile is missing — onboarding resumes at profile creation.
  final bool consentAlreadySubmitted;
}

/// Combines the fresh privacy async and the profile async into one access
/// state. Errors dominate (unavailable), then loading, then the consent/profile
/// matrix. Any error → unavailable, never "missing consent" (§8.2).
final appAccessProvider = Provider<AppAccessState>((ref) {
  final privacy = ref.watch(privacyProvider);
  final profile = ref.watch(childProfileProvider);

  if (privacy.hasError || profile.hasError) {
    return const AppAccessState(AppAccessStatus.unavailable);
  }
  if (privacy.isLoading || profile.isLoading) {
    return const AppAccessState(AppAccessStatus.loading);
  }

  final privacyState = privacy.value!;
  final hasProfile = profile.value != null;
  final consentCurrent = privacyState.acceptedPolicyVersion != null &&
      privacyState.acceptedPolicyVersion == privacyState.currentPolicyVersion;

  if (hasProfile && !consentCurrent) {
    return const AppAccessState(AppAccessStatus.policyReviewRequired);
  }
  if (!hasProfile) {
    return AppAccessState(
      AppAccessStatus.setupRequired,
      consentAlreadySubmitted: consentCurrent,
    );
  }
  return const AppAccessState(AppAccessStatus.ready);
});
