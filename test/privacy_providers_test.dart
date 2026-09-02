import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/profile/profile_providers.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';

/// Controllable [PrivacyRepository]: fetch returns [fetchState]/throws
/// [fetchError] (optionally gated behind [fetchGate]); every update call is
/// recorded and parked on a [Completer] so tests pace responses and assert
/// mutation serialization.
class _FakePrivacyRepository implements PrivacyRepository {
  _FakePrivacyRepository({this.fetchState, this.fetchError});

  PrivacyState? fetchState;
  Object? fetchError;
  Completer<void>? fetchGate;

  int fetchCalls = 0;
  final updateCalls = <({
    String policyVersion,
    bool coreStorageAccepted,
    bool progressTrackingEnabled,
    bool cloudTtsEnabled,
  })>[];
  final updateGates = <Completer<PrivacyState>>[];

  @override
  Future<PrivacyState> fetchPrivacy() async {
    fetchCalls++;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    if (fetchError != null) throw fetchError!;
    return fetchState!;
  }

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
  }) {
    updateCalls.add((
      policyVersion: policyVersion,
      coreStorageAccepted: coreStorageAccepted,
      progressTrackingEnabled: progressTrackingEnabled,
      cloudTtsEnabled: cloudTtsEnabled,
    ));
    final gate = Completer<PrivacyState>();
    updateGates.add(gate);
    return gate.future;
  }

  @override
  Future<void> recordActivity() async {}

  @override
  Future<void> deleteReadingHistory() async {}

  @override
  Future<void> deleteChildData() async {}
}

/// Store whose JSON writes always fail, simulating a full/corrupt disk. Reads
/// still hit SharedPreferences so cache-read behaviour stays realistic.
class _FailingWriteStore extends KeyValueStore {
  _FailingWriteStore(super.prefs);

  @override
  Future<void> writeJson(String key, Object value) async {
    throw StateError('disk full');
  }
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<ChildProfile?> getProfile() async => null;

  @override
  Future<void> saveProfile(ChildProfile profile) async {}

  @override
  bool get hasConsented => false;

  @override
  Future<void> setConsented(bool value) async {}

  @override
  bool get isOnboarded => false;
}

Future<(ProviderContainer, KeyValueStore)> _makeContainer(
  _FakePrivacyRepository repo, {
  Map<String, String> initialValues = const {},
  bool failingCacheWrites = false,
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final store = failingCacheWrites
      ? _FailingWriteStore(await SharedPreferences.getInstance())
      : await KeyValueStore.create();
  final container = ProviderContainer(
    // Riverpod 3 auto-retries failed builds with real timers; disable that so
    // error-path tests resolve immediately.
    retry: (_, _) => null,
    overrides: [
      privacyRepositoryProvider.overrideWithValue(repo),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
      keyValueStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return (container, store);
}

PrivacyState _privacyState({
  String currentPolicyVersion = '2026-09',
  String? acceptedPolicyVersion,
  bool progressTrackingEnabled = false,
  bool cloudTtsEnabled = false,
  bool effectiveProgressTrackingEnabled = false,
  bool effectiveCloudTtsEnabled = false,
}) =>
    PrivacyState(
      currentPolicyVersion: currentPolicyVersion,
      acceptedPolicyVersion: acceptedPolicyVersion,
      reviewRequired: false,
      lastActiveAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      progressTrackingEnabled: progressTrackingEnabled,
      cloudTtsEnabled: cloudTtsEnabled,
      effectiveProgressTrackingEnabled: effectiveProgressTrackingEnabled,
      effectiveCloudTtsEnabled: effectiveCloudTtsEnabled,
    );

void main() {
  group('PrivacyNotifier.build – fetch + cache', () {
    test('exposes the fresh server response and writes the cache', () async {
      final serverState = _privacyState(
        effectiveProgressTrackingEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      final repo = _FakePrivacyRepository(fetchState: serverState);
      final (container, store) = await _makeContainer(repo);

      final state = await container.read(privacyProvider.future);

      expect(state, serverState);
      expect(repo.fetchCalls, 1);
      expect(store.getString('privacy_state_cache'), isNotNull);
      expect(container.read(privacyStateCacheProvider), serverState);
    });

    test(
        'cache provider is display-only: exposed when the fresh fetch errors, '
        'but it never authorizes the effective toggles', () async {
      final cached = _privacyState(
        acceptedPolicyVersion: '2026-09',
        effectiveProgressTrackingEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      final repo = _FakePrivacyRepository(
        fetchError: const PrivacyFailure('offline'),
      );
      final (container, _) = await _makeContainer(
        repo,
        initialValues: {'privacy_state_cache': jsonEncode(cached.toJson())},
      );

      await expectLater(
        container.read(privacyProvider.future),
        throwsA(isA<PrivacyFailure>()),
      );

      expect(container.read(privacyStateCacheProvider), cached);
      expect(container.read(effectiveProgressTrackingProvider), isFalse,
          reason: 'cache must not grant progress tracking');
      expect(container.read(effectiveCloudTtsProvider), isFalse,
          reason: 'cache must not grant cloud narration');
    });
  });

  group('effective toggles – fresh async server result only', () {
    test('false while the fetch is in flight, server value after it lands',
        () async {
      final repo = _FakePrivacyRepository(
        fetchState: _privacyState(
          effectiveProgressTrackingEnabled: true,
          effectiveCloudTtsEnabled: true,
        ),
      )..fetchGate = Completer<void>();
      final (container, _) = await _makeContainer(repo);

      final fetching = container.read(privacyProvider.future);

      expect(container.read(privacyProvider).isLoading, isTrue);
      expect(container.read(effectiveProgressTrackingProvider), isFalse,
          reason: 'defaults before fetch must not grant access');
      expect(container.read(effectiveCloudTtsProvider), isFalse);

      repo.fetchGate!.complete();
      await fetching;

      expect(container.read(effectiveProgressTrackingProvider), isTrue);
      expect(container.read(effectiveCloudTtsProvider), isTrue);
    });

    test('false when the fetch errors', () async {
      final repo = _FakePrivacyRepository(
        fetchError: const PrivacyFailure('offline'),
      );
      final (container, _) = await _makeContainer(repo);

      await expectLater(
        container.read(privacyProvider.future),
        throwsA(isA<PrivacyFailure>()),
      );

      expect(container.read(effectiveProgressTrackingProvider), isFalse);
      expect(container.read(effectiveCloudTtsProvider), isFalse);
    });
  });

  group('PrivacyNotifier.updatePrivacy – serialized mutations', () {
    test(
        'mutations queue: the second update call reaches the server only '
        'after the first response lands; AsyncData comes only from responses',
        () async {
      final repo = _FakePrivacyRepository(fetchState: _privacyState());
      final (container, store) = await _makeContainer(repo);
      final initial = await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final first = notifier.updatePrivacy(
        policyVersion: '2026-09',
        coreStorageAccepted: true,
        progressTrackingEnabled: true,
        cloudTtsEnabled: false,
      );
      final second = notifier.updatePrivacy(
        policyVersion: '2026-09',
        coreStorageAccepted: true,
        progressTrackingEnabled: false,
        cloudTtsEnabled: false,
      );

      // Flush microtasks so the queued mutation closures actually start.
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(1),
          reason: 'the second mutation must await the in-flight first one');
      expect(repo.updateCalls.first.progressTrackingEnabled, isTrue);
      // No optimistic state: still the initial server response.
      expect(container.read(privacyProvider).value, initial);

      final resultA = _privacyState(
        acceptedPolicyVersion: '2026-09',
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
      );
      repo.updateGates[0].complete(resultA);
      await first;
      // Flush microtasks so the queued second mutation actually reaches the
      // repo before the assertion.
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(2));
      expect(repo.updateCalls[1].progressTrackingEnabled, isFalse);
      expect(container.read(privacyProvider).value, resultA);

      final resultB = _privacyState(
        acceptedPolicyVersion: '2026-09',
        progressTrackingEnabled: false,
        effectiveProgressTrackingEnabled: false,
      );
      repo.updateGates[1].complete(resultB);
      await second;

      expect(container.read(privacyProvider).value, resultB);
      expect(container.read(privacyStateCacheProvider), resultB);
      expect(store.getString('privacy_state_cache'),
          jsonEncode(resultB.toJson()));
    });

    test(
        'a failed update keeps the previous server response (retry UI, no '
        'fake authorization), rethrows, and the queue still runs the next '
        'mutation', () async {
      final initial = _privacyState(acceptedPolicyVersion: '2026-09');
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, store) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final failing = notifier.updatePrivacy(
        policyVersion: '2026-09',
        coreStorageAccepted: true,
        progressTrackingEnabled: true,
        cloudTtsEnabled: true,
      );
      // Flush microtasks so the queued mutation closure reaches the repo.
      await Future<void>.delayed(Duration.zero);
      repo.updateGates[0].completeError(const PrivacyFailure('offline'));
      await expectLater(failing, throwsA(isA<PrivacyFailure>()));

      expect(container.read(privacyProvider).value, initial,
          reason: 'failure must not mint new state nor wipe the last response');
      expect(store.getString('privacy_state_cache'),
          jsonEncode(initial.toJson()));

      final next = notifier.updatePrivacy(
        policyVersion: '2026-09',
        coreStorageAccepted: true,
        progressTrackingEnabled: false,
        cloudTtsEnabled: false,
      );
      // Flush microtasks so the queued mutation closure actually starts.
      await Future<void>.delayed(Duration.zero);
      expect(repo.updateCalls, hasLength(2),
          reason: 'a failure must not deadlock the mutation queue');
      final fresh = _privacyState(acceptedPolicyVersion: '2026-09');
      repo.updateGates[1].complete(fresh);
      await next;

      expect(container.read(privacyProvider).value, fresh);
    });
  });

  group('cache write failures are best-effort (display cache only)', () {
    test(
        'build still yields the fresh server response and access is not '
        'unavailable', () async {
      final serverState = _privacyState(
        acceptedPolicyVersion: '2026-09',
        effectiveProgressTrackingEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      final repo = _FakePrivacyRepository(fetchState: serverState);
      final (container, store) = await _makeContainer(
        repo,
        failingCacheWrites: true,
      );

      final state = await container.read(privacyProvider.future);
      // Settle the profile async so the access derivation isn't stuck on
      // loading.
      await container.read(childProfileProvider.future);

      expect(state, serverState);
      expect(container.read(privacyProvider).hasError, isFalse);
      expect(store.getString('privacy_state_cache'), isNull,
          reason: 'the write failed; the cache stays empty');
      expect(container.read(effectiveProgressTrackingProvider), isTrue);
      expect(container.read(effectiveCloudTtsProvider), isTrue);
      expect(container.read(appAccessProvider).status,
          AppAccessStatus.setupRequired,
          reason: 'a cache write failure must not fail access');
    });

    test(
        'cache write failure is best-effort: updatePrivacy still succeeds '
        'with the server response instead of restoring previous/rethrowing',
        () async {
      final initial = _privacyState(acceptedPolicyVersion: '2026-09');
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, store) = await _makeContainer(
        repo,
        failingCacheWrites: true,
      );
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final fresh = _privacyState(
        acceptedPolicyVersion: '2026-09',
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
      );
      final updating = notifier.updatePrivacy(
        policyVersion: '2026-09',
        coreStorageAccepted: true,
        progressTrackingEnabled: true,
        cloudTtsEnabled: false,
      );
      // Flush microtasks so the queued mutation closure reaches the repo.
      await Future<void>.delayed(Duration.zero);
      repo.updateGates[0].complete(fresh);
      await updating;

      expect(container.read(privacyProvider).value, fresh,
          reason: 'the server-committed response must not be discarded');
      expect(container.read(privacyProvider).hasError, isFalse);
      expect(store.getString('privacy_state_cache'), isNull);
    });
  });
}
