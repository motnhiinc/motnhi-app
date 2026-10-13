import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

abstract interface class ScanPagePlayer {
  ValueNotifier<int> get currentLine;
  ValueNotifier<bool> get completed;
  ValueNotifier<bool> get playing;
  Future<void> load(List<File> clips);
  Future<void> play();
  Future<void> pause();
  Future<void> resume();
  Future<void> replay();
  Future<void> stop();
  Future<void> dispose();
}

class LineAudioPlayer implements ScanPagePlayer {
  LineAudioPlayer({AudioPlayer? player, this.onFirstPlaybackProgress})
    : _player = player ?? AudioPlayer();

  final VoidCallback? onFirstPlaybackProgress;

  final AudioPlayer _player;
  @override
  final ValueNotifier<int> currentLine = ValueNotifier(0);
  @override
  final ValueNotifier<bool> completed = ValueNotifier(false);
  @override
  final ValueNotifier<bool> playing = ValueNotifier(false);
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool _firstProgress = false;
  bool _disposed = false;

  @override
  Future<void> load(List<File> clips) async {
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    _firstProgress = false;
    await _player.setAudioSources([
      for (final clip in clips) AudioSource.file(clip.path),
    ]);
    currentLine.value = 0;
    completed.value = false;
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!_disposed && index != null) currentLine.value = index;
    });
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (!_disposed) {
        playing.value =
            state.playing && state.processingState != ProcessingState.completed;
      }
      if (!_disposed && state.processingState == ProcessingState.completed) {
        completed.value = true;
      }
    });
    _positionSubscription = _player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 50),
        )
        .listen((position) {
          if (!_disposed &&
              !_firstProgress &&
              _player.playing &&
              position > Duration.zero) {
            _firstProgress = true;
            onFirstPlaybackProgress?.call();
          }
        });
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.play();
  @override
  Future<void> replay() async {
    await _player.seek(Duration.zero, index: 0);
    currentLine.value = 0;
    completed.value = false;
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    currentLine.value = 0;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    currentLine.dispose();
    completed.dispose();
    playing.dispose();
    await _player.dispose();
  }
}
