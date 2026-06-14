import '../models/models.dart';
import '../sources/key_value_store.dart';

/// Persists parent-controlled reading settings (§7.2.4).
abstract class SettingsRepository {
  Future<ReadingSettings> getSettings();
  Future<void> saveSettings(ReadingSettings settings);
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._store);

  final KeyValueStore _store;

  static const _key = 'reading_settings';

  @override
  Future<ReadingSettings> getSettings() async {
    final json = _store.readJson(_key);
    if (json == null) return const ReadingSettings();
    return ReadingSettings.fromJson(json);
  }

  @override
  Future<void> saveSettings(ReadingSettings settings) =>
      _store.writeJson(_key, settings.toJson());
}
