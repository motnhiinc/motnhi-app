import 'dart:io';

import '../../data/sources/key_value_store.dart';
import '../../data/sources/persistence_keys.dart';

/// Ordered local child-data cleanup (Task 20).
///
/// Runs only after the server confirmed child-data deletion (204): it sets the
/// repair marker first, disposes live narration/scan/AR resources, removes
/// every [childDataKeys] entry (never [preservedKeys]), deletes the generated
/// audio files this app owns, invalidates the provider graph, and clears the
/// marker. An interruption at any point leaves the marker behind, which the
/// bootstrap repair (`repairPendingChildDataCleanup` in main.dart) turns into
/// a retry at the next startup.
class ChildDataCleaner {
  ChildDataCleaner({
    required KeyValueStore store,
    required List<Directory Function()> directories,
    required List<Future<void> Function()> disposers,
    required void Function() invalidateProviders,
  })  : _store = store,
        _directories = List.of(directories),
        _disposers = List.of(disposers),
        _invalidateProviders = invalidateProviders;

  final KeyValueStore _store;

  /// The app-owned cache/temp directories generated audio lives in. Suppliers
  /// are evaluated at cleanup time. Iteration is direct files only.
  final List<Directory Function()> _directories;

  /// Disposes live resources (narration fetchers, scan TTS clients) so nothing
  /// keeps writing owned files while they are being deleted.
  final List<Future<void> Function()> _disposers;
  final void Function() _invalidateProviders;

  /// `scan_any_page_narration.<ext>` plus the HttpTtsClient temporary form
  /// `.<name>.<ext>.<operationId>.tmp`.
  static final RegExp _scanNarrationPattern = RegExp(
    r'^\.?scan_any_page_narration\.(?:mp3|caf|wav)(?:\.\d+\.tmp)?$',
  );

  /// `narration_<segmentId>.mp3` (plus the same temporary form).
  static final RegExp _narrationPattern = RegExp(
    r'^\.?narration_.+\.mp3(?:\.\d+\.tmp)?$',
  );

  /// `ar_<sanitizedStoryId>_p<n>_s<n>.<ext>` plus the atomic-write temporary
  /// form `ar_..._.<ext>.tmp`.
  static final RegExp _arSegmentPattern = RegExp(
    r'^ar_.+_p\d+_s\d+\.(?:mp3|caf|wav)(?:\.tmp)?$',
  );

  static bool _isOwnedAudioName(String name) =>
      _scanNarrationPattern.hasMatch(name) ||
      _narrationPattern.hasMatch(name) ||
      _arSegmentPattern.hasMatch(name);

  /// Marker-first ordered cleanup. See the class doc for the exact order.
  Future<void> clean() async {
    // Marker first: an interruption anywhere below is repairable at the next
    // startup because bootstrap sees the pending marker and re-runs clean().
    await _store.setBool(cleanupPendingKey, true);
    for (final dispose in _disposers) {
      await dispose();
    }
    for (final key in childDataKeys) {
      await _store.remove(key);
    }
    await deleteOwnedAudioFiles(_directories);
    _invalidateProviders();
    await _store.remove(cleanupPendingKey);
  }

  /// Deletes app-owned generated audio. Only DIRECT files of the given
  /// directories are considered — never a recursive delete of a (system) temp
  /// directory — and a missing or unreadable directory is tolerated.
  Future<void> deleteOwnedAudioFiles(
    List<Directory Function()> directories,
  ) async {
    for (final supplier in directories) {
      final Directory directory;
      try {
        directory = supplier();
      } catch (_) {
        continue;
      }
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!_isOwnedAudioName(name)) continue;
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort: a file we cannot delete now is swept by the next
          // bootstrap repair pass.
        }
      }
    }
  }

  /// True when any app-owned generated audio file still exists — the file
  /// half of the bootstrap residue check.
  Future<bool> hasOwnedAudioFiles() async {
    for (final supplier in _directories) {
      final Directory directory;
      try {
        directory = supplier();
      } catch (_) {
        continue;
      }
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (_isOwnedAudioName(entity.uri.pathSegments.last)) return true;
      }
    }
    return false;
  }
}
