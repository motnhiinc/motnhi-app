import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class LineAudioPlayer {
  LineAudioPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final ValueNotifier<int> currentLine = ValueNotifier(0);
  final ValueNotifier<bool> completed = ValueNotifier(false);
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _disposed = false;

  Future<void> load(List<File> clips) async {
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _player.setAudioSources([
      for (final clip in clips) AudioSource.file(clip.path),
    ]);
    currentLine.value = 0;
    completed.value = false;
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!_disposed && index != null) currentLine.value = index;
    });
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (!_disposed && state.processingState == ProcessingState.completed) {
        completed.value = true;
      }
    });
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> replay() async {
    await _player.seek(Duration.zero, index: 0);
    currentLine.value = 0;
    completed.value = false;
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    currentLine.value = 0;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    currentLine.dispose();
    completed.dispose();
    await _player.dispose();
  }
}
