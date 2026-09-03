import '../models/models.dart';
import '../sources/key_value_store.dart';
import '../sources/persistence_keys.dart';

/// Persists parent-controlled reading settings (§7.2.4).
abstract class SettingsRepository {
  Future<ReadingSettings> getSettings();
  Future<void> saveSettings(ReadingSettings settings);
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._store);

  final KeyValueStore _store;

  @override
  Future<ReadingSettings> getSettings() async {
    final json = _store.readJson(readingSettingsKey);
    if (json == null) return const ReadingSettings();
    return ReadingSettings.fromJson(json);
  }

  @override
  Future<void> saveSettings(ReadingSettings settings) =>
      _store.writeJson(readingSettingsKey, settings.toJson());
}
