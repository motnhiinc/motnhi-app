import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/data/sources/persistence_keys.dart';
import 'package:storybook_ar/features/privacy/child_data_cleaner.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';
import 'package:storybook_ar/main.dart' show repairPendingChildDataCleanup;

/// Controllable [PrivacyRepository] for the notifier-level ordering tests.
class _FakePrivacyRepository implements PrivacyRepository {
  _FakePrivacyRepository({this.fetchState});

  PrivacyState? fetchState;
  Object? fetchError;
  Object? deleteChildDataError;

  int fetchCalls = 0;
  int deleteChildDataCalls = 0;

  @override
  Future<PrivacyState> fetchPrivacy() async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    return fetchState!;
  }

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
    required bool pageImageValidationEnabled,
  }) async =>
      fetchState!;

  @override
  Future<void> recordActivity() async {}

  @override
  Future<void> deleteReadingHistory() async {}

  @override
  Future<void> deleteChildData() async {
    deleteChildDataCalls++;
    final error = deleteChildDataError;
    if (error != null) throw error;
  }
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.profile});

  ChildProfile? profile;
  int getProfileCalls = 0;

  @override
  Future<ChildProfile?> getProfile() async {
    getProfileCalls++;
    return profile;
  }

  @override
  Future<void> saveProfile(ChildProfile profile) async {}
}

/// Controllable resource disposer: records calls, optionally parks on a gate
/// and/or throws.
class _DisposerSpy {
  Completer<void>? gate;
  Object? error;
  int calls = 0;

  Future<void> call() async {
    calls++;
    final pending = gate;
    if (pending != null) await pending.future;
    final failure = error;
    if (failure != null) throw failure;
  }
}

/// Cleaner that records invocations without touching store or files.
class _SpyCleaner extends ChildDataCleaner {
  _SpyCleaner(KeyValueStore store)
      : super(
          store: store,
          directories: const [],
          disposers: const [],
          invalidateProviders: () {},
        );

  int calls = 0;

  @override
  Future<void> clean() async => calls++;
}

final _tempDirs = <Directory>[];

Directory _trackTempDir() {
  final dir = Directory.systemTemp.createTempSync('child_cleaner_test');
  _tempDirs.add(dir);
  return dir;
}

Future<KeyValueStore> _storeWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return KeyValueStore.create();
}

ChildDataCleaner _cleaner(
  KeyValueStore store, {
  Directory? directory,
  List<Future<void> Function()> disposers = const [],
  void Function()? onInvalidate,
}) =>
    ChildDataCleaner(
      store: store,
      directories: [
        if (directory != null) () => directory,
      ],
      disposers: disposers,
      invalidateProviders: onInvalidate ?? () {},
    );

PrivacyState _privacyState({String? acceptedPolicyVersion = '2026-09'}) =>
    PrivacyState(
      currentPolicyVersion: '2026-09',
      acceptedPolicyVersion: acceptedPolicyVersion,
      reviewRequired: false,
      lastActiveAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

void main() {
  tearDown(() {
    for (final dir in _tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    _tempDirs.clear();
  });

  group('ChildDataCleaner.clean', () {
    test('removes every child key and preserves device/auth/other keys',
        () async {
      final store = await _storeWith({
        for (final key in preservedKeys) key: 'keep-$key',
        'unregistered_key': 'stays',
        for (final key in childDataKeys) key: 'value',
      });
      final invalidations = <int>[];
      final cleaner =
          _cleaner(store, onInvalidate: () => invalidations.add(1));

      await cleaner.clean();

      expect(store.keys, containsAll(preservedKeys),
          reason: 'device identity, auth credentials, and locale survive');
      expect(store.getString('unregistered_key'), 'stays',
          reason: 'only registered child keys are removed');
      for (final key in childDataKeys) {
        expect(store.keys, isNot(contains(key)), reason: key);
      }
      expect(store.getBool(cleanupPendingKey), isFalse,
          reason: 'a successful cleanup clears the marker');
      expect(invalidations, [1]);
    });

    test('sets the pending marker before touching anything else', () async {
      final store = await _storeWith({});
      final disposer = _DisposerSpy()..gate = Completer<void>();
      final cleaner = _cleaner(store, disposers: [disposer.call]);

      final running = cleaner.clean();
      await Future<void>.delayed(Duration.zero);

      expect(store.getBool(cleanupPendingKey), isTrue,
          reason: 'an interruption from here on is repairable at bootstrap');
      expect(disposer.calls, 1);

      disposer.gate!.complete();
      await running;

      expect(store.getBool(cleanupPendingKey), isFalse);
    });

    test('a throwing disposer keeps the marker; a retry finishes the job',
        () async {
      final store = await _storeWith({childProfileKey: '{"nickname":"kid"}'});
      final disposer = _DisposerSpy()..error = StateError('boom');
      final cleaner = _cleaner(store, disposers: [disposer.call]);

      await expectLater(cleaner.clean(), throwsA(isA<StateError>()));
      expect(store.getBool(cleanupPendingKey), isTrue,
          reason: 'the interrupted cleanup must be repairable at next startup');

      disposer.error = null;
      await cleaner.clean();

      expect(store.getBool(cleanupPendingKey), isFalse);
      expect(store.getString(childProfileKey), isNull);
    });

    test('deletes exactly the owned generated-audio files', () async {
      final store = await _storeWith({});
      final dir = _trackTempDir();
      final owned = [
        'scan_any_page_narration.mp3',
        'scan_any_page_narration.caf',
        'scan_any_page_narration.wav',
        '.scan_any_page_narration.mp3.12.tmp',
        'narration_seg1.mp3',
        'narration_page2.mp3',
        '.narration_seg1.mp3.3.tmp',
        'ar_story1_p1_s0.mp3',
        'ar_story1_p2_s1.caf',
        'ar_story1_p1_s0.wav.tmp',
      ];
      final unrelated = [
        'random.txt',
        'other_prefix.mp3',
        'narrationless.mp3',
        'scan_any_page_narration_backup.mp3',
        'ar_story1_pX_s0.mp3',
        'pre_ar_story1_p1_s0.mp3',
      ];
      for (final name in [...owned, ...unrelated]) {
        File('${dir.path}/$name').writeAsStringSync('x');
      }
      final nested = Directory('${dir.path}/nested')..createSync();
      File('${nested.path}/narration_nested.mp3').writeAsStringSync('x');

      await _cleaner(store, directory: dir).clean();

      for (final name in owned) {
        expect(File('${dir.path}/$name').existsSync(), isFalse, reason: name);
      }
      for (final name in unrelated) {
        expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
      }
      expect(File('${nested.path}/narration_nested.mp3').existsSync(), isTrue,
          reason: 'cleanup must never recurse into subdirectories');
    });

    test('tolerates missing directories', () async {
      final store = await _storeWith({});
      final cleaner = _cleaner(
        store,
        directory: Directory(
          '${Directory.systemTemp.path}/child_cleaner_missing_dir_xyz',
        ),
      );

      await expectLater(cleaner.clean(), completes);
      expect(store.getBool(cleanupPendingKey), isFalse);
    });

    test('hasOwnedAudioFiles detects owned files and reports none after clean',
        () async {
      final store = await _storeWith({});
      final dir = _trackTempDir();
      final cleaner = _cleaner(store, directory: dir);

      expect(await cleaner.hasOwnedAudioFiles(), isFalse);

      File('${dir.path}/narration_seg.mp3').writeAsStringSync('x');
      expect(await cleaner.hasOwnedAudioFiles(), isTrue);

      await cleaner.clean();
      expect(await cleaner.hasOwnedAudioFiles(), isFalse);
    });
  });

  group('PrivacyNotifier.deleteChildData ordering (Task 20)', () {
    test('server failure never invokes the cleaner; success invokes it once',
        () async {
      final store = await _storeWith({});
      final repo = _FakePrivacyRepository(fetchState: _privacyState())
        ..deleteChildDataError = const PrivacyFailure('backend');
      final spy = _SpyCleaner(store);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          privacyRepositoryProvider.overrideWithValue(repo),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
          keyValueStoreProvider.overrideWithValue(store),
          childDataCleanerProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(privacyProvider.future);

      await expectLater(
        container.read(privacyProvider.notifier).deleteChildData(),
        throwsA(isA<PrivacyFailure>()),
      );

      expect(repo.deleteChildDataCalls, 1);
      expect(spy.calls, 0,
          reason: 'local cleanup runs only after server confirmation');

      repo.deleteChildDataError = null;
      await container.read(privacyProvider.notifier).deleteChildData();

      expect(repo.deleteChildDataCalls, 2);
      expect(spy.calls, 1);
    });
  });

  group('bootstrap repair (repairPendingChildDataCleanup)', () {
    ProviderContainer makeContainer({
      required KeyValueStore store,
      required Directory? directory,
      required _FakePrivacyRepository repo,
      required _FakeProfileRepository profileRepo,
    }) {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          privacyRepositoryProvider.overrideWithValue(repo),
          profileRepositoryProvider.overrideWithValue(profileRepo),
          childDataCleanerProvider.overrideWithValue(
            _cleaner(store, directory: directory),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a pending marker runs cleanup before any server round-trip',
        () async {
      final dir = _trackTempDir();
      File('${dir.path}/narration_seg.mp3').writeAsStringSync('x');
      final store = await _storeWith({
        childCleanupPendingKey: true,
        childProfileKey: '{"nickname":"kid"}',
      });
      final repo = _FakePrivacyRepository(fetchState: _privacyState());
      final profileRepo = _FakeProfileRepository();
      final container = makeContainer(
        store: store,
        directory: dir,
        repo: repo,
        profileRepo: profileRepo,
      );

      await repairPendingChildDataCleanup(container);

      expect(repo.fetchCalls, 0,
          reason: 'the marker alone must trigger repair, no server check');
      expect(store.getString(childProfileKey), isNull);
      expect(File('${dir.path}/narration_seg.mp3').existsSync(), isFalse);
      expect(store.getBool(childCleanupPendingKey), isFalse,
          reason: 'the marker is cleared at the end of the successful cleanup');
    });

    test('residue + fresh-null server state + no profile runs cleanup',
        () async {
      final dir = _trackTempDir();
      File('${dir.path}/ar_story1_p1_s0.mp3').writeAsStringSync('x');
      final store = await _storeWith({storySessionsKey: '[]'});
      final repo = _FakePrivacyRepository(
        fetchState: _privacyState(acceptedPolicyVersion: null),
      );
      final profileRepo = _FakeProfileRepository(profile: null);
      final container = makeContainer(
        store: store,
        directory: dir,
        repo: repo,
        profileRepo: profileRepo,
      );

      await repairPendingChildDataCleanup(container);

      expect(repo.fetchCalls, 1);
      expect(profileRepo.getProfileCalls, 1);
      expect(store.getString(storySessionsKey), isNull,
          reason: 'post-deletion residue is cleaned');
      expect(File('${dir.path}/ar_story1_p1_s0.mp3').existsSync(), isFalse);
      expect(store.getBool(childCleanupPendingKey), isFalse);
    });

    test('residue but an active child on the server keeps local data',
        () async {
      final dir = _trackTempDir();
      final store = await _storeWith({storySessionsKey: '[]'});
      final repo = _FakePrivacyRepository(
        fetchState: _privacyState(acceptedPolicyVersion: '2026-09'),
      );
      final profileRepo =
          _FakeProfileRepository(profile: const ChildProfile(id: 'p1', ageBand: AgeBand.threeToFour));
      final container = makeContainer(
        store: store,
        directory: dir,
        repo: repo,
        profileRepo: profileRepo,
      );

      await repairPendingChildDataCleanup(container);

      expect(repo.fetchCalls, 1);
      expect(profileRepo.getProfileCalls, 0,
          reason: 'an accepted policy short-circuits before the profile check');
      expect(store.getString(storySessionsKey), '[]');
      expect(store.getBool(childCleanupPendingKey), isFalse,
          reason: 'no cleanup ran, so no marker may linger');
    });

    test('a clean store never touches the server', () async {
      final store = await _storeWith({deviceIdKey: 'device-1'});
      final repo = _FakePrivacyRepository(fetchState: _privacyState());
      final profileRepo = _FakeProfileRepository();
      final container = makeContainer(
        store: store,
        directory: null,
        repo: repo,
        profileRepo: profileRepo,
      );

      await repairPendingChildDataCleanup(container);

      expect(repo.fetchCalls, 0);
      expect(profileRepo.getProfileCalls, 0);
    });

    test('unconfirmed server state (offline) keeps local data', () async {
      final dir = _trackTempDir();
      final store = await _storeWith({storySessionsKey: '[]'});
      final repo = _FakePrivacyRepository(fetchState: _privacyState())
        ..fetchError = const PrivacyFailure('offline');
      final profileRepo = _FakeProfileRepository();
      final container = makeContainer(
        store: store,
        directory: dir,
        repo: repo,
        profileRepo: profileRepo,
      );

      await repairPendingChildDataCleanup(container);

      expect(store.getString(storySessionsKey), '[]',
          reason: 'deletion is only ever run on confirmed server state');
      expect(store.getBool(childCleanupPendingKey), isFalse);
    });
  });
}
