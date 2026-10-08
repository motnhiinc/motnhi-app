import 'package:flutter/services.dart';

import 'ar_character.dart';
import 'ar_reader_diagnostic.dart';
import 'ar_narration_bundle.dart';

class StoryReaderSupport {
  const StoryReaderSupport({required this.supported, this.diagnostic});

  final bool supported;
  final ArReaderDiagnostic? diagnostic;
}

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
  bool get scanNextRequested => terminalCode == 'scan_next';
}

final class StoryReaderFailure implements Exception {
  const StoryReaderFailure(this.code, {this.diagnostic});

  final String code;
  final ArReaderDiagnostic? diagnostic;

  @override
  String toString() => 'StoryReaderFailure($code)';
}

abstract interface class StoryReader {
  /// Cheap capability probe, asked before any narration is prepared so an
  /// unsupported device never shows the AR button at all.
  Future<StoryReaderSupport> isSupported();

  /// Opens the native AR reader on [pages], starting at [initialPageIndex].
  /// [character] is the doll the child picked: [ArCharacter.assetBaseName]
  /// names the bundled `.glb`/`.usdz` model the native side loads, while
  /// [ArCharacter.id] rides along as stable diagnostics metadata — native
  /// bridges currently ignore it, but it keeps the wire self-describing for
  /// future logging without another contract change.
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
    bool scannedPageMode = false,
  });
}

final class NativeStoryReader implements StoryReader {
  NativeStoryReader({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('storybook_ar/character_reader');

  final MethodChannel _channel;

  @override
  Future<StoryReaderSupport> isSupported() async {
    try {
      final response =
          await _channel.invokeMethod<Object?>('isStoryReaderSupported');
      if (response is bool) {
        return StoryReaderSupport(supported: response);
      }
      if (response is Map) {
        return StoryReaderSupport(
          supported: response['supported'] == true,
          diagnostic: ArReaderDiagnostic.fromWire(response['diagnostics']),
        );
      }
      return const StoryReaderSupport(supported: false);
    } on PlatformException catch (error) {
      return StoryReaderSupport(
        supported: false,
        diagnostic: ArReaderDiagnostic.fromWire(error.details),
      );
    } on MissingPluginException {
      // Desktop, or a build without the native reader. Not an error worth
      // surfacing — it just means no AR button.
      return const StoryReaderSupport(supported: false);
    }
  }

  @override
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
    bool scannedPageMode = false,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'openStoryReader',
        {
          'pages': [for (final page in pages) page.toJson()],
          'initialPageIndex': initialPageIndex,
          'characterId': character.id,
          'modelAssetBaseName': character.assetBaseName,
          if (scannedPageMode) 'scannedPageMode': true,
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
      throw StoryReaderFailure(
        error.code,
        diagnostic: ArReaderDiagnostic.fromWire(error.details),
      );
    } on MissingPluginException {
      throw const StoryReaderFailure('ar_unavailable');
    }
  }
}
