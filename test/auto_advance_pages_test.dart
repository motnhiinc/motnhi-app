import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/data/sources/persistence_keys.dart';
import 'package:storybook_ar/features/settings/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('page turning starts on and parent choice persists', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.create();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(autoAdvancePagesProvider), isTrue);
    await container.read(autoAdvancePagesProvider.notifier).set(false);
    expect(container.read(autoAdvancePagesProvider), isFalse);
    expect(store.getBool(settingsAutoAdvancePagesKey, fallback: true), isFalse);
  });
}
