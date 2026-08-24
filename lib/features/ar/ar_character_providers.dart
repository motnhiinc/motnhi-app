import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import 'ar_character.dart';

/// Store key for the persisted character selection.
const selectedArCharacterIdKey = 'ar.selected_character_id';

/// Currently selected AR character. Seeded from the store on startup; null,
/// missing, or unknown stored ids sanitize back to the default fox via
/// [arCharacterById].
final selectedArCharacterProvider =
    NotifierProvider<SelectedArCharacterNotifier, ArCharacter>(
  SelectedArCharacterNotifier.new,
);

class SelectedArCharacterNotifier extends Notifier<ArCharacter> {
  @override
  ArCharacter build() => arCharacterById(
        ref.watch(keyValueStoreProvider).getString(selectedArCharacterIdKey),
      );

  Future<void> select(ArCharacter character) async {
    state = character;
    await ref
        .read(keyValueStoreProvider)
        .setString(selectedArCharacterIdKey, character.id);
  }
}
