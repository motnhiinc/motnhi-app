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

  Future<StoryReaderResult?> start() async {
    if (_busy) return null;
    _busy = true;
    try {
      value = value.copyWith(phase: ArReaderPhase.checkingSupport);
      if (!await reader.isSupported()) {
        return _fail('ar_unsupported');
      }

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
          onProgress: (done, total) =>
              value = value.copyWith(prepared: done, total: total),
        );
      } on ArNarrationFailure catch (error) {
        return _fail(error.code);
      } catch (_) {
        return _fail('narration_unavailable');
      }

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
        return _fail(error.code);
      }
    } finally {
      _busy = false;
    }
  }

  StoryReaderResult? _fail(String code) {
    value = value.copyWith(phase: ArReaderPhase.failure, failureCode: code);
    return null;
  }
}
