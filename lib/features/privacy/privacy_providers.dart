import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../profile/profile_providers.dart';

/// Local SharedPreferences key holding the last server privacy response.
/// Display cache only — never consulted for authorization (§14).
const _privacyStateCacheKey = 'privacy_state_cache';

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
  final json = ref.watch(keyValueStoreProvider).readJson(_privacyStateCacheKey);
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

  /// Best-effort: the display cache must never block or discard a server
  /// response the server already committed — a write failure is swallowed so
  /// build()/updatePrivacy() critical paths stay unaffected.
  Future<void> _writeCache(PrivacyState fresh) async {
    try {
      await ref
          .read(keyValueStoreProvider)
          .writeJson(_privacyStateCacheKey, fresh.toJson());
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
enum AppAccessStatus { loading, setupRequired, policyReviewRequired, ready, unavailable }

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
