import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';

void main() {
  group('AR character catalog integrity', () {
    test('selectable ids and asset base names are nonempty and unique', () {
      expect(arCharacters, isNotEmpty);
      final ids = <String>{};
      final assetBaseNames = <String>{};

      for (final character in arCharacters) {
        expect(character.id.trim(), isNotEmpty);
        expect(
          ids.add(character.id),
          isTrue,
          reason: 'Duplicate selectable id: ${character.id}',
        );
        expect(character.assetBaseName, isNotEmpty);
        expect(
          assetBaseNames.add(character.assetBaseName),
          isTrue,
          reason: 'Duplicate model base name: ${character.assetBaseName}',
        );
        expect(arCharacterById(character.id), same(character));
      }
    });

    test('every model base name satisfies both native bridge allowlists', () {
      // CharacterReaderBridge.kt modelAssetFileName and
      // CharacterReaderBridge.swift safeModelAssetBaseName use this pattern.
      final allowedBaseName = RegExp(r'^[a-z0-9_]+$');

      for (final character in arCharacters) {
        expect(
          allowedBaseName.stringMatch(character.assetBaseName),
          character.assetBaseName,
          reason: '${character.id} must reach native model lookup unchanged',
        );
      }
    });

    test(
      'every selectable model has nonempty Android and iOS bundle files',
      () {
        for (final character in arCharacters) {
          final baseName = character.assetBaseName;
          for (final path in [
            'android/app/src/main/assets/$baseName.glb',
            'ios/Runner/CharacterReader/$baseName.usdz',
          ]) {
            final model = File(path);
            expect(
              model.existsSync(),
              isTrue,
              reason: '${character.id} requires bundled model $path',
            );
            expect(
              model.lengthSync(),
              greaterThan(0),
              reason: '$path must not be an empty placeholder',
            );
          }
        }
      },
    );

    test('missing, retired or invalid selections resolve to the dinosaur', () {
      final fallback = arCharacterById('little_buddy');
      expect(fallback.id, 'little_buddy');
      expect(fallback.assetBaseName, 'little_buddy');
      expect(arCharacters.first, same(fallback));

      for (final id in <String?>[
        null,
        '',
        'fox_default',
        'cute_doll_v01',
        'little_buddy_preview',
        'unknown_character',
        '../cute_doll_v01',
        'CUTE_DOLL_V01',
        'cute_doll_v01.glb',
      ]) {
        expect(
          arCharacterById(id),
          same(fallback),
          reason: 'Invalid selection $id must fall back to the dinosaur',
        );
      }
    });
  });
}
