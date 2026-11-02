import 'package:flutter/foundation.dart';

/// One AR character the reader can wear. [id] keys the selection state and
/// [displayName] is the human-facing label shown in pickers.
@immutable
class ArCharacter {
  const ArCharacter({
    required this.id,
    required this.displayName,
    required this.assetBaseName,
  });

  final String id;
  final String displayName;

  /// Base name of the bundled model files: `<base>.glb` on Android and
  /// `<base>.usdz` on iOS.
  final String assetBaseName;
}

/// One companion for both scan and story reading, in debug and release builds.
const dinosaurCharacter = ArCharacter(
  id: 'little_buddy',
  displayName: 'Little Buddy',
  assetBaseName: 'little_buddy',
);

const arCharacters = <ArCharacter>[dinosaurCharacter];

/// Returns the character with [id], falling back to the first catalog entry
/// (the dinosaur) for null, retired, or unknown ids.
ArCharacter arCharacterById(String? id) => arCharacters.firstWhere(
  (character) => character.id == id,
  orElse: () => arCharacters.first,
);
