import '../../data/repositories/privacy_repository.dart';
import '../../data/sources/key_value_store.dart';
import '../../data/sources/persistence_keys.dart';

/// Reports daily child-app usage to the server (§14, `POST
/// /v1/privacy/activity`), throttled to one report per UTC day via
/// [privacyActivityLastUtcDateKey]. Kept deliberately as a plain class: it
/// holds no state a widget would render — the privacy/access state in
/// `privacy_providers.dart` is never touched here.
///
/// Best-effort by contract: a failed report is swallowed (the key is written
/// only after success, so the next foreground retries) and never disturbs
/// consent or access routing.
class PrivacyActivityNotifier {
  PrivacyActivityNotifier({
    required KeyValueStore store,
    required PrivacyRepository repository,
    required DateTime Function() clock,
  })  : _store = store,
        _repository = repository,
        _clock = clock;

  final KeyValueStore _store;
  final PrivacyRepository _repository;
  final DateTime Function() _clock;

  bool _inFlight = false;

  /// Called when the app returns to the foreground (`resumed` only).
  Future<void> onForeground() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final today = _utcDateKey(_clock());
      if (_store.getString(privacyActivityLastUtcDateKey) == today) return;
      await _repository.recordActivity();
      await _store.setString(privacyActivityLastUtcDateKey, today);
    } catch (_) {
      // Best-effort report: a failure (network, storage) must not alter
      // privacy/access state. Without a stored date the next foreground
      // simply retries.
    } finally {
      _inFlight = false;
    }
  }

  /// `yyyy-MM-dd` of the injected clock's UTC date.
  String _utcDateKey(DateTime now) {
    final utc = now.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
