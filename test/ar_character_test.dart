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
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('arCharacters catalog', () {
    test('leads with the fox backed by the scan-any-page asset', () {
      final fox = arCharacters.first;
      expect(fox.id, 'fox_default');
      expect(fox.displayName, 'Fox');
      expect(fox.assetBaseName, 'scan_any_page_character');
    });

    test('offers exactly six doll variants whose ids equal their assets', () {
      final dolls = arCharacters
          .where((character) => character.id.startsWith('cute_doll_v'))
          .toList();

      expect(dolls, hasLength(6));
      for (var i = 0; i < dolls.length; i++) {
        expect(dolls[i].id, 'cute_doll_v0${i + 1}');
        expect(dolls[i].assetBaseName, 'cute_doll_v0${i + 1}');
        expect(dolls[i].displayName, 'Doll ${i + 1}');
      }
    });
  });

  group('arCharacterById', () {
    test('returns the matching character for a known id', () {
      expect(arCharacterById('cute_doll_v02').displayName, 'Doll 2');
      expect(arCharacterById('fox_default').assetBaseName,
          'scan_any_page_character');
    });

    test('falls back to the fox for null', () {
      expect(arCharacterById(null).id, 'fox_default');
    });

    test('sanitizes unknown ids back to the fox', () {
      expect(arCharacterById('../evil').id, 'fox_default');
      expect(arCharacterById('nope').id, 'fox_default');
    });
  });

  group('selectedArCharacterProvider', () {
    test('defaults to Fox when nothing is stored', () async {
      final container = await containerOverStore({});

      expect(container.read(selectedArCharacterProvider).id, 'fox_default');
    });

    test('select() updates state and persists the chosen id', () async {
      final container = await containerOverStore({});
      final doll3 = arCharacterById('cute_doll_v03');

      await container.read(selectedArCharacterProvider.notifier).select(doll3);

      expect(container.read(selectedArCharacterProvider).id, 'cute_doll_v03');
      expect(storeOf(container).getString('ar.selected_character_id'),
          'cute_doll_v03');
    });

    test('restores a previously selected doll on startup', () async {
      final container = await containerOverStore({
        'ar.selected_character_id': 'cute_doll_v05',
      });

      expect(container.read(selectedArCharacterProvider).displayName, 'Doll 5');
    });

    test('sanitizes garbage stored ids back to Fox', () async {
      final container = await containerOverStore({
        'ar.selected_character_id': 'evil',
      });

      expect(container.read(selectedArCharacterProvider).id, 'fox_default');
    });
  });
}

KeyValueStore storeOf(ProviderContainer container) =>
    container.read(keyValueStoreProvider);
