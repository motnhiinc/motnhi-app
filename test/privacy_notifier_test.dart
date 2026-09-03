import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';

/// Controllable [PrivacyRepository]: fetch/update are gated and recorded so
/// tests pace server responses and assert mutation serialization; deletes are
/// recorded with optional failure injection.
class _FakePrivacyRepository implements PrivacyRepository {
  _FakePrivacyRepository({this.fetchState});

  PrivacyState? fetchState;
  Object? fetchError;
  Completer<void>? fetchGate;

  int fetchCalls = 0;
  int deleteReadingHistoryCalls = 0;
  int deleteChildDataCalls = 0;

  /// When set, [deleteChildData] throws instead of succeeding.
  Object? deleteChildDataError;

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
  Future<void> deleteReadingHistory() async {
    deleteReadingHistoryCalls++;
  }

  @override
  Future<void> deleteChildData() async {
    deleteChildDataCalls++;
    final error = deleteChildDataError;
    if (error != null) throw error;
  }
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<ChildProfile?> getProfile() async => null;

  @override
  Future<void> saveProfile(ChildProfile profile) async {}
}

Future<(ProviderContainer, KeyValueStore)> _makeContainer(
  _FakePrivacyRepository repo, {
  Map<String, String> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final store = await KeyValueStore.create();
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
  String? acceptedPolicyVersion = '2026-09',
  bool progressTrackingEnabled = false,
  bool cloudTtsEnabled = false,
  bool effectiveProgressTrackingEnabled = false,
  bool effectiveCloudTtsEnabled = false,
  PrivacyDataCounts counts = const PrivacyDataCounts(),
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
      counts: counts,
    );

void main() {
  group('PrivacyNotifier parent operations – option updates (Task 17)', () {
    test(
        'two rapid setProgressTracking calls serialize: PUTs reach the server '
        'in order and the second body is built from the first response',
        () async {
      final initial = _privacyState(
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          storySessions: 2,
          interactionEvents: 7,
        ),
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final first = notifier.setProgressTracking(true);
      final second = notifier.setProgressTracking(false);

      // Flush microtasks so the queued mutation closures actually start.
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(1),
          reason: 'the second update must await the in-flight first one');
      expect(repo.updateCalls.first.policyVersion, '2026-09');
      expect(repo.updateCalls.first.coreStorageAccepted, isTrue);
      expect(repo.updateCalls.first.progressTrackingEnabled, isTrue);
      expect(repo.updateCalls.first.cloudTtsEnabled, isFalse);
      // No optimistic state before the server responds.
      expect(container.read(privacyProvider).value, initial);

      final afterOn = _privacyState(
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
      );
      repo.updateGates[0].complete(afterOn);
      await first;
      // Flush microtasks so the queued second mutation reaches the repo.
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(2));
      expect(repo.updateCalls[1].policyVersion, '2026-09',
          reason: 'policy version must come from the first server response');
      expect(repo.updateCalls[1].coreStorageAccepted, isTrue);
      expect(repo.updateCalls[1].progressTrackingEnabled, isFalse);
      expect(repo.updateCalls[1].cloudTtsEnabled, isFalse,
          reason: 'unchanged choices are resent from the first response');

      final afterOff = _privacyState();
      repo.updateGates[1].complete(afterOff);
      await second;

      // Server responses replace local state.
      expect(container.read(privacyProvider).value, afterOff);
      expect(container.read(privacyStateCacheProvider), afterOff);
      expect(repo.deleteReadingHistoryCalls, 0,
          reason: 'option updates must never delete history');
    });

    test('setCloudTts sends the current-policy body and the server response '
        'replaces local state', () async {
      final initial = _privacyState(
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final updating = notifier.setCloudTts(true);
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(1));
      expect(repo.updateCalls.first.policyVersion, '2026-09');
      expect(repo.updateCalls.first.coreStorageAccepted, isTrue);
      expect(repo.updateCalls.first.progressTrackingEnabled, isTrue,
          reason: 'the complete current-policy body is resent');
      expect(repo.updateCalls.first.cloudTtsEnabled, isTrue);

      final cloudOn = _privacyState(
        progressTrackingEnabled: true,
        cloudTtsEnabled: true,
        effectiveProgressTrackingEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      repo.updateGates[0].complete(cloudOn);
      await updating;

      expect(container.read(privacyProvider).value, cloudOn);
      expect(container.read(effectiveCloudTtsProvider), isTrue);
    });

    test(
        'setProgressTracking(false) completes only after the server confirmed '
        'tracking off, and never deletes history itself (dismissal retains '
        'history)', () async {
      final initial = _privacyState(
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          storySessions: 3,
          interactionEvents: 12,
        ),
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final turningOff = notifier.setProgressTracking(false);
      await Future<void>.delayed(Duration.zero);

      // Before the server response: state and effective toggle unchanged —
      // the future has not completed, so the UI cannot open the
      // retain/delete dialog yet.
      expect(container.read(privacyProvider).value, initial);
      expect(container.read(effectiveProgressTrackingProvider), isTrue);

      final afterOff = _privacyState(
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          storySessions: 3,
          interactionEvents: 12,
        ),
      );
      repo.updateGates[0].complete(afterOff);
      await turningOff;

      // Future completes post-update: server confirmed tracking off, history
      // retained on the server, no delete issued by the notifier.
      expect(container.read(effectiveProgressTrackingProvider), isFalse);
      expect(container.read(privacyProvider).value, afterOff);
      expect(repo.deleteReadingHistoryCalls, 0,
          reason: 'deletion is only ever an explicit parent choice');
    });

    test('option-update failure keeps the previous server response and '
        'rethrows (retry UI)', () async {
      final initial = _privacyState(
        progressTrackingEnabled: true,
        effectiveProgressTrackingEnabled: true,
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final failing = notifier.setProgressTracking(false);
      await Future<void>.delayed(Duration.zero);
      repo.updateGates[0].completeError(const PrivacyFailure('offline'));

      await expectLater(failing, throwsA(isA<PrivacyFailure>()));
      expect(container.read(privacyProvider).value, initial);
      expect(container.read(effectiveProgressTrackingProvider), isTrue,
          reason: 'a failed update must not flip the effective toggle');

      final retrying = notifier.setProgressTracking(false);
      await Future<void>.delayed(Duration.zero);
      expect(repo.updateCalls, hasLength(2),
          reason: 'a failure must not deadlock the mutation queue');
      final afterOff = _privacyState();
      repo.updateGates[1].complete(afterOff);
      await retrying;
      expect(container.read(privacyProvider).value, afterOff);
    });
  });

  group('PrivacyNotifier.deleteReadingHistory', () {
    test(
        'calls the repository delete, then refetches privacy state so counts '
        'change', () async {
      final initial = _privacyState(
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          storySessions: 2,
          interactionEvents: 5,
        ),
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final cleared = _privacyState();
      // The next fetch (after the delete) returns the cleared state.
      repo.fetchState = cleared;

      final deleting = container
          .read(privacyProvider.notifier)
          .deleteReadingHistory();
      await Future<void>.delayed(Duration.zero);
      expect(repo.deleteReadingHistoryCalls, 1);

      await deleting;
      expect(repo.fetchCalls, 2,
          reason: 'privacy state is refetched after the delete');
      expect(container.read(privacyProvider).value, cleared);
      expect(container.read(privacyStateCacheProvider), cleared);
    });

    test('deletes queue behind in-flight option updates', () async {
      final repo = _FakePrivacyRepository(fetchState: _privacyState());
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      final notifier = container.read(privacyProvider.notifier);
      final updating = notifier.setCloudTts(true);
      final deleting = notifier.deleteReadingHistory();
      await Future<void>.delayed(Duration.zero);

      expect(repo.updateCalls, hasLength(1));
      expect(repo.deleteReadingHistoryCalls, 0,
          reason: 'the delete must await the in-flight update');

      final cloudOn = _privacyState(
        cloudTtsEnabled: true,
        effectiveCloudTtsEnabled: true,
      );
      repo.updateGates[0].complete(cloudOn);
      await updating;
      await deleting;

      expect(repo.deleteReadingHistoryCalls, 1);
    });

    test('a failed delete keeps the previous server response and rethrows',
        () async {
      final initial = _privacyState(
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          storySessions: 2,
          interactionEvents: 5,
        ),
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, _) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      // Subsequent fetches (the post-delete refetch) fail.
      repo.fetchError = const PrivacyFailure('offline');

      final deleting = container
          .read(privacyProvider.notifier)
          .deleteReadingHistory();
      await expectLater(deleting, throwsA(isA<PrivacyFailure>()));

      expect(container.read(privacyProvider).value, initial,
          reason: 'failure must not mint new state nor wipe the last response');
    });
  });

  group('PrivacyNotifier.deleteChildData', () {
    test(
        'failure retains state, surfaces the error, and leaves the local '
        'throttle key; retry succeeds and clears the key', () async {
      final initial = _privacyState(
        counts: const PrivacyDataCounts(
          childProfiles: 1,
          authoredStories: 2,
          storySessions: 4,
          interactionEvents: 9,
        ),
      );
      final repo = _FakePrivacyRepository(fetchState: initial);
      final (container, store) = await _makeContainer(
        repo,
        initialValues: {
          'privacy_activity_last_utc_date': '2026-09-01T00:00:00.000Z',
        },
      );
      await container.read(privacyProvider.future);

      repo.deleteChildDataError = const PrivacyFailure('backend');
      await expectLater(
        container.read(privacyProvider.notifier).deleteChildData(),
        throwsA(isA<PrivacyFailure>()),
      );

      expect(repo.deleteChildDataCalls, 1);
      expect(container.read(privacyProvider).value, initial,
          reason: 'failure must leave the retained state untouched');
      expect(store.getString('privacy_activity_last_utc_date'), isNotNull,
          reason: 'a failed deletion must not clear the local throttle key');

      // Retry succeeds.
      repo.deleteChildDataError = null;
      await container.read(privacyProvider.notifier).deleteChildData();

      expect(repo.deleteChildDataCalls, 2);
      expect(store.getString('privacy_activity_last_utc_date'), isNull,
          reason: 'the local tracking throttle key is cleared after deletion');
    });

    test('the throttle key removal is skipped cleanly when the key is absent',
        () async {
      final repo = _FakePrivacyRepository(fetchState: _privacyState());
      final (container, store) = await _makeContainer(repo);
      await container.read(privacyProvider.future);

      await container.read(privacyProvider.notifier).deleteChildData();

      expect(repo.deleteChildDataCalls, 1);
      expect(store.getString('privacy_activity_last_utc_date'), isNull);
    });
  });
}
