import 'package:flutter/services.dart';

import 'ar_character.dart';
import 'ar_narration_bundle.dart';

/// How an AR reading ended, and how far it got.
///
/// `cancelled` is not a failure: it is the normal way to leave AR, and it still
/// carries the page the child reached so the book can reopen there.
class StoryReaderResult {
  const StoryReaderResult({
    required this.terminalCode,
    required this.lastPageId,
    required this.pagesRead,
  });

  final String terminalCode;
  final String? lastPageId;

  /// Every page that actually began playing, in the order it was heard. The
  /// player records these as `page_viewed` events, because pages read inside AR
  /// never pass through its own page-load path.
  final List<String> pagesRead;

  bool get completed => terminalCode == 'completed';
}

final class StoryReaderFailure implements Exception {
  const StoryReaderFailure(this.code);

  final String code;

  @override
  String toString() => 'StoryReaderFailure($code)';
}

abstract interface class StoryReader {
  /// Cheap capability probe, asked before any narration is prepared so an
  /// unsupported device never shows the AR button at all.
  Future<bool> isSupported();

  /// Opens the native AR reader on [pages], starting at [initialPageIndex].
  /// [character] is the doll the child picked: its [ArCharacter.assetBaseName]
  /// names the bundled `.glb`/`.usdz` model the native side loads, and
  /// [ArCharacter.id] travels along so native logs can attribute a session.
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
  });
}

final class NativeStoryReader implements StoryReader {
  NativeStoryReader({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('storybook_ar/character_reader');

  final MethodChannel _channel;

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isStoryReaderSupported') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Desktop, or a build without the native reader. Not an error worth
      // surfacing — it just means no AR button.
      return false;
    }
  }

  @override
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'openStoryReader',
        {
          'pages': [for (final page in pages) page.toJson()],
          'initialPageIndex': initialPageIndex,
          'characterId': character.id,
          'modelAssetBaseName': character.assetBaseName,
        },
      );
      return StoryReaderResult(
        // Both platforms reply on the success channel for completed and
        // cancelled alike; anything else arrives as a PlatformException.
        terminalCode: raw?['terminalCode'] as String? ?? 'cancelled',
        lastPageId: raw?['lastPageId'] as String?,
        pagesRead:
            (raw?['pagesRead'] as List?)?.cast<String>() ?? const <String>[],
      );
    } on PlatformException catch (error) {
      throw StoryReaderFailure(error.code);
    } on MissingPluginException {
      throw const StoryReaderFailure('ar_unavailable');
    }
  }
}
