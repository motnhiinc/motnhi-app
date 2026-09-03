import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/core/router/app_router.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/profile/profile_providers.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';

class _FakePrivacyRepository implements PrivacyRepository {
  _FakePrivacyRepository({this.state, this.error, this.hangs = false});

  final PrivacyState? state;
  final Object? error;

  /// Never completes: keeps [privacyProvider] in AsyncLoading.
  final bool hangs;

  @override
  Future<PrivacyState> fetchPrivacy() async {
    if (hangs) return Completer<PrivacyState>().future;
    if (error != null) throw error!;
    return state!;
  }

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> recordActivity() async {}

  @override
  Future<void> deleteReadingHistory() async {}

  @override
  Future<void> deleteChildData() async {}
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.profile, this.error, this.hangs = false});

  final ChildProfile? profile;
  final Object? error;

  /// Never completes: keeps [childProfileProvider] in AsyncLoading.
  final bool hangs;

  @override
  Future<ChildProfile?> getProfile() async {
    if (hangs) return Completer<ChildProfile?>().future;
    if (error != null) throw error!;
    return profile;
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {}
}

const _currentPolicy = '2026-09';

PrivacyState _privacyState({
  String? acceptedPolicyVersion,
  bool effectiveProgressTrackingEnabled = false,
  bool effectiveCloudTtsEnabled = false,
}) =>
    PrivacyState(
      currentPolicyVersion: _currentPolicy,
      acceptedPolicyVersion: acceptedPolicyVersion,
      reviewRequired: false,
      lastActiveAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      effectiveProgressTrackingEnabled: effectiveProgressTrackingEnabled,
      effectiveCloudTtsEnabled: effectiveCloudTtsEnabled,
    );

ChildProfile _profile() =>
    const ChildProfile(id: 'child-1', ageBand: AgeBand.fiveToSix);

Future<ProviderContainer> _pumpContainer({
  PrivacyState? privacyState,
  Object? privacyError,
  bool privacyHangs = false,
  ChildProfile? profile,
  Object? profileError,
  bool profileHangs = false,
  Map<String, String> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final store = await KeyValueStore.create();
  final container = ProviderContainer(
    // Riverpod 3 auto-retries failed builds with real timers; disable that so
    // error-path tests resolve immediately.
    retry: (_, _) => null,
    overrides: [
      privacyRepositoryProvider.overrideWithValue(
        _FakePrivacyRepository(
          state: privacyState,
          error: privacyError,
          hangs: privacyHangs,
        ),
      ),
      profileRepositoryProvider.overrideWithValue(
        _FakeProfileRepository(
          profile: profile,
          error: profileError,
          hangs: profileHangs,
        ),
      ),
      keyValueStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Awaits both async inputs, swallowing errors so error-state tests can then
/// assert on the derived access state. Never call this in loading tests (the
/// hanging futures would never resolve).
Future<void> _settle(ProviderContainer container) async {
  try {
    await container.read(privacyProvider.future);
  } catch (_) {}
  try {
    await container.read(childProfileProvider.future);
  } catch (_) {}
}

void main() {
  group('appAccessProvider – access-state matrix', () {
    test('privacy loading → loading (even with a profile)', () async {
      final container = await _pumpContainer(
        privacyHangs: true,
        profile: _profile(),
      );

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.loading);
    });

    test('profile loading → loading (even with current consent)', () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: _currentPolicy),
        profileHangs: true,
      );

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.loading);
    });

    test('privacy error → unavailable', () async {
      final container = await _pumpContainer(
        privacyError: const PrivacyFailure('offline'),
        profile: _profile(),
      );
      await _settle(container);

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.unavailable);
    });

    test('profile error → unavailable', () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: _currentPolicy),
        profileError: Exception('profile fetch failed'),
      );
      await _settle(container);

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.unavailable);
    });

    test('no consent + no profile → setupRequired, consent not submitted',
        () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: null),
        profile: null,
      );
      await _settle(container);

      final access = container.read(appAccessProvider);
      expect(access.status, AppAccessStatus.setupRequired);
      expect(access.consentAlreadySubmitted, isFalse);
    });

    test(
        'accepted (current) + no profile → setupRequired, consent already '
        'submitted', () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: _currentPolicy),
        profile: null,
      );
      await _settle(container);

      final access = container.read(appAccessProvider);
      expect(access.status, AppAccessStatus.setupRequired);
      expect(access.consentAlreadySubmitted, isTrue);
    });

    test('stale consent + existing profile → policyReviewRequired', () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: '2025-01'),
        profile: _profile(),
      );
      await _settle(container);

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.policyReviewRequired);
    });

    test('no acceptance at all + existing profile → policyReviewRequired',
        () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: null),
        profile: _profile(),
      );
      await _settle(container);

      expect(container.read(appAccessProvider).status,
          AppAccessStatus.policyReviewRequired);
    });

    test('current consent + existing profile → ready', () async {
      final container = await _pumpContainer(
        privacyState: _privacyState(acceptedPolicyVersion: _currentPolicy),
        profile: _profile(),
      );
      await _settle(container);

      expect(
          container.read(appAccessProvider).status, AppAccessStatus.ready);
    });

    test(
        'privacy optional values before fetch must not grant access: with a '
        'pre-seeded cache claiming enabled toggles, the effective providers '
        'stay false while the fresh fetch is in flight', () async {
      final cached = _privacyState(
        acceptedPolicyVersion: _currentPolicy,
        effectiveProgressTrackingEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      final container = await _pumpContainer(
        privacyHangs: true,
        profile: _profile(),
        initialValues: {'privacy_state_cache': jsonEncode(cached.toJson())},
      );

      final access = container.read(appAccessProvider);
      expect(access.status, AppAccessStatus.loading);
      expect(container.read(effectiveProgressTrackingProvider), isFalse);
      expect(container.read(effectiveCloudTtsProvider), isFalse);
    });
  });

  group('appAccessRedirect – router redirect matrix', () {
    test('loading and unavailable force onboarding', () {
      for (final status in [
        AppAccessStatus.loading,
        AppAccessStatus.unavailable,
      ]) {
        expect(appAccessRedirect(AppAccessState(status), AppRoutes.home),
            AppRoutes.onboarding);
        expect(
          appAccessRedirect(AppAccessState(status), AppRoutes.privacyReview),
          AppRoutes.onboarding,
        );
        expect(
          appAccessRedirect(AppAccessState(status), AppRoutes.onboarding),
          isNull,
        );
      }
    });

    test('setupRequired allows onboarding and the privacy notice only', () {
      const access = AppAccessState(AppAccessStatus.setupRequired);
      expect(appAccessRedirect(access, AppRoutes.home),
          AppRoutes.onboarding);
      expect(appAccessRedirect(access, AppRoutes.privacyReview),
          AppRoutes.onboarding);
      expect(appAccessRedirect(access, AppRoutes.onboarding), isNull);
      expect(appAccessRedirect(access, AppRoutes.privacyNotice), isNull);
    });

    test('policyReviewRequired forces the privacy review route', () {
      const access = AppAccessState(AppAccessStatus.policyReviewRequired);
      expect(appAccessRedirect(access, AppRoutes.home),
          AppRoutes.privacyReview);
      expect(appAccessRedirect(access, AppRoutes.onboarding),
          AppRoutes.privacyReview);
      expect(appAccessRedirect(access, AppRoutes.privacyReview), isNull);
      expect(appAccessRedirect(access, AppRoutes.privacyNotice), isNull);
    });

    test('ready releases the app and bounces back out of setup routes', () {
      const access = AppAccessState(AppAccessStatus.ready);
      expect(appAccessRedirect(access, AppRoutes.onboarding), AppRoutes.home);
      expect(
          appAccessRedirect(access, AppRoutes.privacyReview), AppRoutes.home);
      expect(appAccessRedirect(access, AppRoutes.home), isNull);
      expect(appAccessRedirect(access, AppRoutes.privacyNotice), isNull,
          reason: '/privacy-notice stays ungated');
      expect(appAccessRedirect(access, AppRoutes.gate), isNull,
          reason: 'the /parent* gate handles the rest');
    });
  });
}
