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

/// Catalog of AR models bundled with the app. The fox (the scan-any-page
/// character) comes first because it doubles as the fallback selection.
const arCharacters = <ArCharacter>[
  ArCharacter(
    id: 'fox_default',
    displayName: 'Fox',
    assetBaseName: 'scan_any_page_character',
  ),
  ArCharacter(id: 'cute_doll_v01', displayName: 'Doll 1', assetBaseName: 'cute_doll_v01'),
  ArCharacter(id: 'cute_doll_v02', displayName: 'Doll 2', assetBaseName: 'cute_doll_v02'),
  ArCharacter(id: 'cute_doll_v03', displayName: 'Doll 3', assetBaseName: 'cute_doll_v03'),
  ArCharacter(id: 'cute_doll_v04', displayName: 'Doll 4', assetBaseName: 'cute_doll_v04'),
  ArCharacter(id: 'cute_doll_v05', displayName: 'Doll 5', assetBaseName: 'cute_doll_v05'),
  ArCharacter(id: 'cute_doll_v06', displayName: 'Doll 6', assetBaseName: 'cute_doll_v06'),
];

/// Returns the character with [id], falling back to the first catalog entry
/// (the fox) for null or unknown ids.
ArCharacter arCharacterById(String? id) => arCharacters.firstWhere(
      (character) => character.id == id,
      orElse: () => arCharacters.first,
    );
