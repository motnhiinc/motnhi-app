import 'dart:io';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';
import '../player/narration_audio_fetcher.dart';

/// One page of prepared AR narration: the page's clips, in `sort_order`.
///
/// A page is deliberately a *list* of clips rather than one file. Curated pages
/// carry several narration segments, and joining them is not possible in
/// general - a page can legitimately mix an `.mp3` from the backend with a
/// `.caf` written by iOS speech synthesis.
class ArNarrationPage {
  const ArNarrationPage({
    required this.pageId,
    required this.pageNumber,
    required this.audioFilePaths,
  });

  final String pageId;
  final int pageNumber;
  final List<String> audioFilePaths;

  Map<String, dynamic> toJson() => {
        'pageId': pageId,
        'pageNumber': pageNumber,
        'audioFilePaths': audioFilePaths,
      };
}

final class ArNarrationFailure implements Exception {
  const ArNarrationFailure(this.code);

  final String code;

  @override
  String toString() => 'ArNarrationFailure($code)';
}

/// Writes a spoken clip to an exact path.
///
/// Abstracted over `flutter_tts` so the bundle is testable, and so the
/// platform-specific container format lives in exactly one place.
abstract interface class TtsFileSynthesizer {
  /// `caf` on iOS, `wav` on Android. iOS cannot encode MP3.
  String get fileExtension;

  Future<bool> synthesizeToFile(String text, String filePath);
}

/// Fetches the bytes behind a signed asset URL.
abstract interface class ArAudioDownloader {
  Future<List<int>> download(String url);
}

/// `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>`.
///
/// Story-scoped because the directory outlives a single run: without the story
/// id, a failed preparation would leave the previous story's clip in place,
/// still passing the native validator, and AR would narrate the wrong book.
///
/// [pageNumber] and [sortOrder] are the domain values, never list indices.
String arSegmentFileName({
  required String storyId,
  required int pageNumber,
  required int sortOrder,
  required String extension,
}) {
  final stripped = storyId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  // The native validators require 1..32 characters, so an id that sanitizes to
  // nothing still has to produce a legal name.
  final safe = stripped.isEmpty ? 'x' : stripped;
  final scoped = safe.length > 32 ? safe.substring(0, 32) : safe;
  return 'ar_${scoped}_p${pageNumber}_s$sortOrder.$extension';
}

String _storyFilePrefix(String storyId) {
  final name = arSegmentFileName(
    storyId: storyId,
    pageNumber: 0,
    sortOrder: 0,
    extension: 'mp3',
  );
  return name.substring(0, name.indexOf('_p'));
}

/// Prepares one local audio file per narration segment, ready for the native
/// story reader.
///
/// Resolution order per segment: a registered clip's signed URL, then the
/// authored-story TTS fetcher, then on-device speech synthesis. Preparation is
/// all-or-nothing: a partial bundle would break the page-id mapping and risk
/// playing a stale clip.
///
/// [isCancelled] is polled before every file write (and before each remaining
/// unit). When it turns true, preparation throws
/// `ArNarrationFailure('cancelled')` without writing anything further — the
/// hook is what lets child-data cleanup pre-empt a live preparation without
/// the preparation re-creating swept audio files.
Future<List<ArNarrationPage>> prepareArNarration({
  required StoryDetail detail,
  required AssetUrlResolver resolver,
  required NarrationAudioFetcher? fetcher,
  required TtsFileSynthesizer tts,
  required ArAudioDownloader downloader,
  required Directory directory,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final storyId = detail.story.id;
  final pages = detail.orderedPages;

  await _deleteStaleClips(directory, _storyFilePrefix(storyId));

  final units = <_Unit>[];
  for (final page in pages) {
    final segments = detail.segmentsForPage(page.id);
    if (segments.isEmpty) {
      // No segment row at all: speak the page text so the page is never silent.
      units.add(_Unit(page: page, segment: null, text: page.pageText ?? ''));
      continue;
    }
    for (final segment in segments) {
      units.add(_Unit(page: page, segment: segment, text: segment.text));
    }
  }

  final assetIds = [
    for (final unit in units)
      if (unit.segment?.hasAudioAsset ?? false) unit.segment!.audioAssetId!,
  ];
  final urls = assetIds.isEmpty
      ? const <String, String>{}
      : await resolver.resolve(assetIds);

  final pathsByPageId = <String, List<String>>{};
  var done = 0;
  for (final unit in units) {
    _throwIfCancelled(isCancelled);
    final path = await _prepareUnit(
      unit: unit,
      storyId: storyId,
      urls: urls,
      fetcher: fetcher,
      tts: tts,
      downloader: downloader,
      directory: directory,
      isCancelled: isCancelled,
    );
    pathsByPageId.putIfAbsent(unit.page.id, () => <String>[]).add(path);
    onProgress?.call(++done, units.length);
  }

  return [
    for (final page in pages)
      ArNarrationPage(
        pageId: page.id,
        pageNumber: page.pageNumber,
        audioFilePaths: pathsByPageId[page.id] ?? const <String>[],
      ),
  ];
}

class _Unit {
  _Unit({required this.page, required this.segment, required this.text});

  final StoryPage page;
  final NarrationSegment? segment;
  final String text;

  int get sortOrder => segment?.sortOrder ?? 0;
}

/// Throws `ArNarrationFailure('cancelled')` when the caller cancelled, so a
/// cancelled preparation never writes another owned audio file.
void _throwIfCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const ArNarrationFailure('cancelled');
  }
}

Future<String> _prepareUnit({
  required _Unit unit,
  required String storyId,
  required Map<String, String> urls,
  required NarrationAudioFetcher? fetcher,
  required TtsFileSynthesizer tts,
  required ArAudioDownloader downloader,
  required Directory directory,
  required bool Function()? isCancelled,
}) async {
  String target(String extension) => '${directory.path}/'
      '${arSegmentFileName(
        storyId: storyId,
        pageNumber: unit.page.pageNumber,
        sortOrder: unit.sortOrder,
        extension: extension,
      )}';

  final segment = unit.segment;

  // 1. A registered clip.
  final url =
      segment != null && segment.hasAudioAsset ? urls[segment.audioAssetId] : null;
  if (url != null) {
    try {
      final bytes = await downloader.download(url);
      _throwIfCancelled(isCancelled);
      if (bytes.isNotEmpty) return _writeAtomically(target('mp3'), bytes);
    } catch (error) {
      if (error is ArNarrationFailure) rethrow;
      // Fall through: a failed download must not lose the page.
    }
  }

  // 2. The authored-story fetcher. Copy, never rename - the fetcher's cached
  // Future keeps handing the player the original path.
  if (segment != null && fetcher != null) {
    try {
      final source = await fetcher.pathFor(segment);
      _throwIfCancelled(isCancelled);
      if (source != null && await File(source).exists()) {
        return _copyAtomically(source, target('mp3'));
      }
    } catch (error) {
      if (error is ArNarrationFailure) rethrow;
      // Fall through to speech synthesis.
    }
  }

  // 3. On-device speech.
  final text = unit.text.trim();
  if (text.isNotEmpty) {
    _throwIfCancelled(isCancelled);
    final path = target(tts.fileExtension);
    final ok = await tts.synthesizeToFile(text, path);
    if (ok && await File(path).exists()) return path;
  }

  throw const ArNarrationFailure('narration_unavailable');
}

/// Writes via a temporary file so a half-written clip can never pass the native
/// validator - the temporary name is not on its allowlist.
Future<String> _writeAtomically(String path, List<int> bytes) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(path);
  return path;
}

Future<String> _copyAtomically(String source, String path) async {
  final temporary = File('$path.tmp');
  await File(source).copy(temporary.path);
  await temporary.rename(path);
  return path;
}

Future<void> _deleteStaleClips(Directory directory, String prefix) async {
  if (!await directory.exists()) return;
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name.startsWith('${prefix}_p')) {
      try {
        await entity.delete();
      } catch (_) {
        // A clip we cannot delete is overwritten below; not fatal.
      }
    }
  }
}
