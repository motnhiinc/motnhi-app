import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_character_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds a container over a real [KeyValueStore] backed by mocked prefs
  /// seeded with [initialValues].
  Future<ProviderContainer> containerOverStore(
    Map<String, Object> initialValues,
  ) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final store = KeyValueStore(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('arCharacters catalog', () {
    test('offers only the dinosaur in every build', () {
      expect(arCharacters, [dinosaurCharacter]);
      expect(dinosaurCharacter.assetBaseName, 'little_buddy');
    });
  });

  group('arCharacterById', () {
    test('returns the matching character for a known id', () {
      expect(arCharacterById('little_buddy'), same(dinosaurCharacter));
    });

    test('falls back to the dinosaur for null', () {
      expect(arCharacterById(null), same(dinosaurCharacter));
    });

    test('sanitizes unknown and retired ids back to the dinosaur', () {
      for (final id in [
        '../evil',
        'nope',
        'fox_default',
        'cute_doll_v02',
        'little_buddy_preview',
      ]) {
        expect(arCharacterById(id), same(dinosaurCharacter));
      }
    });
  });

  group('selectedArCharacterProvider', () {
    test('defaults to dinosaur when nothing is stored', () async {
      final container = await containerOverStore({});

      expect(
        container.read(selectedArCharacterProvider),
        same(dinosaurCharacter),
      );
    });

    test('select() updates state and persists the chosen id', () async {
      final container = await containerOverStore({});
      const retired = ArCharacter(
        id: 'cute_doll_v03',
        displayName: 'Doll 3',
        assetBaseName: 'cute_doll_v03',
      );

      await container
          .read(selectedArCharacterProvider.notifier)
          .select(retired);

      expect(
        container.read(selectedArCharacterProvider),
        same(dinosaurCharacter),
      );
      expect(
        storeOf(container).getString('ar.selected_character_id'),
        'little_buddy',
      );
    });

    test(
      'migrates a previously selected doll to the dinosaur on startup',
      () async {
        final container = await containerOverStore({
          'ar.selected_character_id': 'cute_doll_v05',
        });

        expect(
          container.read(selectedArCharacterProvider),
          same(dinosaurCharacter),
        );
      },
    );

    test('sanitizes garbage stored ids back to dinosaur', () async {
      final container = await containerOverStore({
        'ar.selected_character_id': 'evil',
      });

      expect(
        container.read(selectedArCharacterProvider),
        same(dinosaurCharacter),
      );
    });
  });
}

KeyValueStore storeOf(ProviderContainer container) =>
    container.read(keyValueStoreProvider);
