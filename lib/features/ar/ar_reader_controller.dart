import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../../data/sources/asset_url_resolver.dart';
import '../player/narration_audio_fetcher.dart';
import 'ar_character.dart';
import 'ar_narration_bundle.dart';
import 'native_story_reader.dart';

enum ArReaderPhase {
  idle,
  checkingSupport,
  preparing,
  opening,
  reading,
  failure,
}

@immutable
class ArReaderState {
  const ArReaderState({
    this.phase = ArReaderPhase.idle,
    this.prepared = 0,
    this.total = 0,
    this.failureCode,
    this.result,
  });

  final ArReaderPhase phase;
  final int prepared;
  final int total;
  final String? failureCode;
  final StoryReaderResult? result;

  ArReaderState copyWith({
    ArReaderPhase? phase,
    int? prepared,
    int? total,
    String? failureCode,
    StoryReaderResult? result,
  }) =>
      ArReaderState(
        phase: phase ?? this.phase,
        prepared: prepared ?? this.prepared,
        total: total ?? this.total,
        failureCode: failureCode ?? this.failureCode,
        result: result ?? this.result,
      );
}

/// Sequences probe -> prepare -> open -> return for an AR reading.
///
/// Holds no Flutter widget types, so the whole flow is unit-testable. The
/// capability probe runs *before* preparation on purpose: narration can take
/// several seconds, and a device that cannot show AR should never make a child
/// wait for it.
class ArReaderController extends ValueNotifier<ArReaderState> {
  ArReaderController({
    required this.detail,
    required this.reader,
    required this.character,
    required this.resolver,
    required this.fetcher,
    required this.tts,
    required this.downloader,
    required this.directory,
    required this.initialPageIndex,
  }) : super(const ArReaderState());

  final StoryDetail detail;
  final StoryReader reader;

  /// The character the child picked; the native reader loads its model files.
  final ArCharacter character;
  final AssetUrlResolver resolver;

  /// The player's own fetcher instance, never a freshly built one: its cache is
  /// what stops an authored story re-issuing a TTS request per page.
  final NarrationAudioFetcher? fetcher;

  final TtsFileSynthesizer tts;
  final ArAudioDownloader downloader;
  final Directory directory;
  final int initialPageIndex;

  bool _busy = false;
  int _generation = 0;

  /// The in-flight [start] run, if any. [cancel] awaits it so a caller that
  /// disposes through `cancel` — the player's registered live-resource
  /// disposer — knows every owned-file write has stopped when it returns.
  Future<StoryReaderResult?>? _inFlight;

  /// Cancels an in-flight [start]: the checkpoints between its phases abort
  /// before the reader opens, and preparation stops writing narration files
  /// at its next per-unit checkpoint (Task 20 lets child-data cleanup pre-empt
  /// a live AR preparation). The returned future settles only once the
  /// cancelled run itself has settled, so a disposer awaiting [cancel] can
  /// sweep owned audio files the moment it completes. A later [start] runs
  /// normally again.
  Future<void> cancel() async {
    _generation++;
    await _inFlight;
  }

  bool _isCancelled(int generation) => generation != _generation;

  Future<StoryReaderResult?> start() async {
    if (_busy) return null;
    _busy = true;
    final generation = ++_generation;
    final Future<StoryReaderResult?> run = _run(generation);
    _inFlight = run;
    try {
      return await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
      _busy = false;
    }
  }

  Future<StoryReaderResult?> _run(int generation) async {
    value = value.copyWith(phase: ArReaderPhase.checkingSupport);
    if (!await reader.isSupported()) {
      return _isCancelled(generation) ? null : _fail('ar_unsupported');
    }
    if (_isCancelled(generation)) return null;

    value = value.copyWith(phase: ArReaderPhase.preparing);
    final List<ArNarrationPage> pages;
    try {
      pages = await prepareArNarration(
        detail: detail,
        resolver: resolver,
        fetcher: fetcher,
        tts: tts,
        downloader: downloader,
        directory: directory,
        onProgress: (done, total) {
          if (_isCancelled(generation)) return;
          value = value.copyWith(prepared: done, total: total);
        },
        isCancelled: () => _isCancelled(generation),
      );
    } on ArNarrationFailure catch (error) {
      return _isCancelled(generation) ? null : _fail(error.code);
    } catch (_) {
      return _isCancelled(generation) ? null : _fail('narration_unavailable');
    }
    if (_isCancelled(generation)) return null;

    value = value.copyWith(phase: ArReaderPhase.opening);
    try {
      final result = await reader.open(
        pages: pages,
        initialPageIndex: initialPageIndex,
        character: character,
      );
      value = value.copyWith(phase: ArReaderPhase.reading, result: result);
      return result;
    } on StoryReaderFailure catch (error) {
      return _isCancelled(generation) ? null : _fail(error.code);
    }
  }

  StoryReaderResult? _fail(String code) {
    value = value.copyWith(phase: ArReaderPhase.failure, failureCode: code);
    return null;
  }
}
