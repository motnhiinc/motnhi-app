import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_character_reader.dart';
import 'native_scan_service.dart';
import 'tts_client.dart';

enum ScanAnyPagePhase {
  idle,
  scanning,
  reviewingText,
  generatingAudio,
  readyForAr,
  openingAr,
  failure,
}

class ScanAnyPageState {
  const ScanAnyPageState({
    this.phase = ScanAnyPagePhase.idle,
    this.recognizedText = '',
    this.confirmedText = '',
    this.audioFile,
    this.failureCode,
  });

  final ScanAnyPagePhase phase;
  final String recognizedText;
  final String confirmedText;
  final File? audioFile;
  final String? failureCode;

  ScanAnyPageState copyWith({
    ScanAnyPagePhase? phase,
    String? recognizedText,
    String? confirmedText,
    Object? audioFile = _unset,
    Object? failureCode = _unset,
  }) {
    return ScanAnyPageState(
      phase: phase ?? this.phase,
      recognizedText: recognizedText ?? this.recognizedText,
      confirmedText: confirmedText ?? this.confirmedText,
      audioFile:
          identical(audioFile, _unset) ? this.audioFile : audioFile as File?,
      failureCode: identical(failureCode, _unset)
          ? this.failureCode
          : failureCode as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScanAnyPageState &&
        other.phase == phase &&
        other.recognizedText == recognizedText &&
        other.confirmedText == confirmedText &&
        other.audioFile == audioFile &&
        other.failureCode == failureCode;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        recognizedText,
        confirmedText,
        audioFile,
        failureCode,
      );
}

const _unset = Object();

class ScanAnyPageController extends Notifier<ScanAnyPageState> {
  ScanAnyPageController({
    required ScanService scanService,
    required TtsClient ttsClient,
    required CharacterReader characterReader,
  })  : _scanService = scanService,
        _ttsClient = ttsClient,
        _characterReader = characterReader;

  static const _maximumTextLength = 4000;

  final ScanService _scanService;
  final TtsClient _ttsClient;
  final CharacterReader _characterReader;
  var _generation = 0;
  var _disposed = false;

  @override
  ScanAnyPageState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      unawaited(_ttsClient.dispose().catchError((_) {}));
    });
    return const ScanAnyPageState();
  }

  Future<void> startScan() async {
    final generation = ++_generation;
    state = const ScanAnyPageState(phase: ScanAnyPagePhase.scanning);
    try {
      final text = await _scanService.scanAndRecognize();
      if (!_isCurrent(generation)) return;
      state = ScanAnyPageState(
        phase: ScanAnyPagePhase.reviewingText,
        recognizedText: text,
      );
    } on ScanCancelled {
      if (!_isCurrent(generation)) return;
      state = const ScanAnyPageState();
    } on ScanFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'scan:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = const ScanAnyPageState(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'scan:unknown',
      );
    }
  }

  Future<void> confirmText(String text) => _generateAudio(text);

  Future<void> retryTts() => _generateAudio(state.confirmedText);

  Future<void> _generateAudio(String input) async {
    final generation = ++_generation;
    final text = input.trim();
    if (text.isEmpty || text.runes.length > _maximumTextLength) {
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'tts:invalid_text',
      );
      return;
    }

    state = state.copyWith(
      phase: ScanAnyPagePhase.generatingAudio,
      confirmedText: text,
      audioFile: null,
      failureCode: null,
    );
    try {
      final file = await _ttsClient.generate(text);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.readyForAr,
        audioFile: file,
        failureCode: null,
      );
    } on TtsGenerationFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'tts:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'tts:unknown',
      );
    }
  }

  Future<void> openCharacterReader() async {
    final generation = ++_generation;
    final file = state.audioFile;
    if (file == null) {
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'ar:missing_audio',
      );
      return;
    }

    state = state.copyWith(
      phase: ScanAnyPagePhase.openingAr,
      failureCode: null,
    );
    try {
      await _characterReader.open(file.path);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.readyForAr,
        failureCode: null,
      );
    } on CharacterReaderCancelled {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.readyForAr,
        failureCode: null,
      );
    } on CharacterReaderFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'ar:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: ScanAnyPagePhase.failure,
        failureCode: 'ar:unknown',
      );
    }
  }

  Future<void> reset() async {
    _generation++;
    state = const ScanAnyPageState();
    await _ttsClient.dispose();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}
