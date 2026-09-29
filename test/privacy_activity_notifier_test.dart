import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/data/sources/persistence_keys.dart';
import 'package:storybook_ar/features/privacy/privacy_activity_notifier.dart';

/// Controllable [PrivacyRepository]: only [recordActivity] is observed.
class _FakePrivacyRepository implements PrivacyRepository {
  Object? recordActivityError;

  int recordActivityCalls = 0;

  @override
  Future<void> recordActivity() async {
    recordActivityCalls++;
    final error = recordActivityError;
    if (error != null) throw error;
  }

  @override
  Future<PrivacyState> fetchPrivacy() async => throw UnimplementedError();

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
    required bool pageImageValidationEnabled,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteReadingHistory() async {}

  @override
  Future<void> deleteChildData() async {}
}

Future<(KeyValueStore, _FakePrivacyRepository, PrivacyActivityNotifier)>
    _makeNotifier({
  required DateTime Function() clock,
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final store = await KeyValueStore.create();
  final repo = _FakePrivacyRepository();
  final notifier = PrivacyActivityNotifier(
    store: store,
    repository: repo,
    clock: clock,
  );
  return (store, repo, notifier);
}

/// `yyyy-MM-dd` of the clock's UTC date — the exact format the notifier must
/// persist under [privacyActivityLastUtcDateKey].
String _expectedUtcDate(DateTime utc) {
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

void main() {
  test('first foreground records activity and writes the UTC date key only '
      'after success', () async {
    var now = DateTime.utc(2026, 9, 3, 9, 30);
    final (store, repo, notifier) = await _makeNotifier(clock: () => now);

    await notifier.onForeground();

    expect(repo.recordActivityCalls, 1);
    expect(store.getString(privacyActivityLastUtcDateKey), '2026-09-03');
    expect(store.getString(privacyActivityLastUtcDateKey),
        _expectedUtcDate(now),
        reason: 'the stored value is yyyy-MM-dd of the injected UTC clock');
  });

  test('repeated foregrounds on the same UTC date are throttled', () async {
    var now = DateTime.utc(2026, 9, 3, 9, 30);
    final (store, repo, notifier) = await _makeNotifier(clock: () => now);

    await notifier.onForeground();
    now = DateTime.utc(2026, 9, 3, 22, 0);
    await notifier.onForeground();
    await notifier.onForeground();

    expect(repo.recordActivityCalls, 1,
        reason: 'same UTC date must not send again');
    expect(store.getString(privacyActivityLastUtcDateKey), '2026-09-03');
  });

  test('the next UTC date sends again and updates the key', () async {
    var now = DateTime.utc(2026, 9, 3, 23, 50);
    final (store, repo, notifier) = await _makeNotifier(clock: () => now);

    await notifier.onForeground();

    now = DateTime.utc(2026, 9, 4, 0, 10);
    await notifier.onForeground();

    expect(repo.recordActivityCalls, 2);
    expect(store.getString(privacyActivityLastUtcDateKey), '2026-09-04');
  });

  test('a failed recordActivity is swallowed: no key write, and the next '
      'foreground retries', () async {
    var now = DateTime.utc(2026, 9, 3, 9, 30);
    final (store, repo, notifier) = await _makeNotifier(clock: () => now);
    repo.recordActivityError = const PrivacyFailure('network');

    // Must complete normally, not rethrow to the lifecycle caller.
    await notifier.onForeground();

    expect(repo.recordActivityCalls, 1);
    expect(store.getString(privacyActivityLastUtcDateKey), isNull,
        reason: 'the throttle key is written only after success');

    // Recovery: still no stored date, so the next foreground retries.
    repo.recordActivityError = null;
    await notifier.onForeground();

    expect(repo.recordActivityCalls, 2);
    expect(store.getString(privacyActivityLastUtcDateKey), '2026-09-03');
  });

  test('the throttle key is child data: full deletion clears it', () async {
    expect(childDataKeys, contains(privacyActivityLastUtcDateKey));
  });
}
