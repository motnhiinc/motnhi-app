import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../features/profile/profile_providers.dart';
import '../../l10n/app_localizations.dart';
import '../ar/ar_character_providers.dart';
import '../ar/ar_narration_bundle.dart';
import '../ar/native_story_reader.dart';
import 'scan_child_states.dart';
import 'line_audio_player.dart';
import 'native_scan_service.dart';
import 'page_image_view.dart';
import 'page_validation_client.dart';
import 'scanned_page.dart';
import 'scanned_page_ar_audio.dart';
import 'scanned_page_preprocessor.dart';

enum _PagePhase {
  scanning,
  preparing,
  ready,
  playing,
  paused,
  blocked,
  failed,
  setup,
}

class ScanAnyPageScreen extends ConsumerStatefulWidget {
  const ScanAnyPageScreen({super.key});

  @override
  ConsumerState<ScanAnyPageScreen> createState() => _ScanAnyPageScreenState();
}

class _ScanAnyPageScreenState extends ConsumerState<ScanAnyPageScreen> {
  late final PageValidationClient _client;
  late final LineAudioPlayer _player;
  late final List<Future<void> Function()> _liveDisposers;
  late final Future<void> Function() _disposeResources;
  final List<File> _clips = [];
  ScannedPage? _page;
  String? _profileId;
  _PagePhase _phase = _PagePhase.scanning;
  int _generation = 0;
  String? _failureCode;
  ScannedPageArAudio _arAudio = ScannedPageArAudio();
  bool _arSupported = false;
  bool _arBusy = false;
  bool _resourcesDisposed = false;
  late final Future<void> _arSupportProbe;

  @override
  void initState() {
    super.initState();
    _client = PageValidationClient(ref.read(apiClientProvider));
    _player = LineAudioPlayer();
    _liveDisposers = ref.read(liveResourceDisposersProvider);
    Future<void>? disposal;
    _disposeResources = () => disposal ??= _releaseResources();
    _liveDisposers.add(_disposeResources);
    _arSupportProbe = _probeArSupport();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _generation++;
    _liveDisposers.remove(_disposeResources);
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _releaseResources() async {
    _resourcesDisposed = true;
    _generation++;
    await _arAudio.dispose();
    await _client.dispose();
    await _player.dispose();
  }

  Future<void> _probeArSupport() async {
    try {
      final support = await ref.read(storyReaderProvider).isSupported();
      if (mounted && !_resourcesDisposed) {
        setState(() => _arSupported = support.supported);
      }
    } catch (_) {
      // Listen remains available if the capability probe fails.
    }
  }

  Future<void> _scan() async {
    if (!mounted || _resourcesDisposed || _arBusy) return;
    final generation = ++_generation;
    setState(() {
      _phase = _PagePhase.scanning;
      _page = null;
      _failureCode = null;
    });
    await _player.stop();
    await _arAudio.dispose();
    if (!mounted || generation != _generation) return;
    _arAudio = ScannedPageArAudio();
    await _clearClips();
    var step = 'profile';
    final timer = Stopwatch()..start();
    void logStage(String event) {
      debugPrint(
        'Scan Any Page: attempt=$generation, stage=$step, event=$event, '
        'elapsed_ms=${timer.elapsedMilliseconds}',
      );
    }

    logStage('started');
    try {
      final profile = await ref.read(childProfileProvider.future);
      if (!mounted || generation != _generation) return;
      if (profile == null) {
        logStage('profile_missing');
        setState(() => _phase = _PagePhase.setup);
        return;
      }
      _profileId = profile.id;
      step = 'capture';
      logStage('started');
      final captured = await ref.read(scanServiceProvider).scanAndRecognize();
      if (!mounted || generation != _generation) return;
      debugPrint(
        'Scan Any Page: attempt=$generation, stage=capture, event=completed, '
        'line_count=${captured.lines.length}, image_bytes=${captured.jpegBytes.length}, '
        'width=${captured.width}, height=${captured.height}, '
        'elapsed_ms=${timer.elapsedMilliseconds}',
      );
      step = 'preprocess';
      final page = preprocessScannedPage(captured);
      debugPrint(
        'Scan Any Page: attempt=$generation, stage=preprocess, event=completed, '
        'line_count=${page.lines.length}, elapsed_ms=${timer.elapsedMilliseconds}',
      );
      setState(() => _phase = _PagePhase.preparing);
      step = 'validation';
      logStage('started');
      final result = await _client.validate(page, profile.id);
      if (!mounted || generation != _generation) return;
      if (result.blocked || result.proof == null) {
        logStage('blocked');
        setState(() => _phase = _PagePhase.blocked);
        return;
      }
      logStage('approved');
      step = 'audio';
      logStage('started');
      final clips = await _client.prepareAudio(
        result.proof!,
        profile.id,
        page.lines.map((line) => line.text).toList(),
      );
      if (!mounted || generation != _generation) {
        for (final clip in clips) {
          if (await clip.exists()) await clip.delete();
        }
        return;
      }
      _clips.addAll(clips);
      debugPrint(
        'Scan Any Page: attempt=$generation, stage=audio, event=completed, '
        'clip_count=${clips.length}, expected_count=${page.lines.length}, '
        'elapsed_ms=${timer.elapsedMilliseconds}',
      );
      if (clips.length != page.lines.length ||
          page.lines.any((line) => !line.isValid)) {
        logStage('invalid_clips_or_lines');
        setState(() => _phase = _PagePhase.failed);
        return;
      }
      step = 'player_load';
      logStage('started');
      final playerLoadTimer = Stopwatch()..start();
      await _player.load(clips);
      logStage('completed');
      debugPrint(
        'Scan Any Page: attempt=$generation, stage=player_load, '
        'player_load_ms=${playerLoadTimer.elapsedMilliseconds}',
      );
      if (mounted && generation == _generation) {
        setState(() {
          _page = page;
          _phase = _PagePhase.ready;
        });
        await _arSupportProbe;
        if (!mounted || _resourcesDisposed || generation != _generation) return;
        final currentProfile = ref.read(childProfileProvider).value;
        if (currentProfile?.id != _profileId) {
          await _stopAndWipe();
          if (mounted && generation == _generation) {
            setState(() => _phase = _PagePhase.setup);
          }
          return;
        }
        if (_arSupported && currentProfile?.arEnabled == true) {
          step = 'ar_reader';
          logStage('started');
          await _openArReader();
        } else {
          step = 'playback';
          logStage('started');
          await _listen();
        }
      }
    } on ScanCancelled {
      logStage('cancelled');
      if (mounted && generation == _generation) context.pop();
    } catch (error) {
      if (mounted && generation == _generation) {
        final code = error is ScanFailure ? error.code : error.runtimeType;
        debugPrint('Scan Any Page failed at $step: $code');
        debugPrint(
          'Scan Any Page: attempt=$generation, stage=$step, event=failed, '
          'error_type=${error.runtimeType}, '
          'http_status=${error is DioException ? error.response?.statusCode : null}, '
          'dio_type=${error is DioException ? error.type.name : null}, '
          'elapsed_ms=${timer.elapsedMilliseconds}',
        );
        setState(() {
          _failureCode = '$step: $code';
          _phase = _PagePhase.failed;
        });
      }
    }
  }

  Future<void> _listen() async {
    if (_arBusy || _resourcesDisposed || _phase != _PagePhase.ready) return;
    final generation = _generation;
    try {
      if (_profileId == null) {
        await _stopAndWipe();
        if (mounted) setState(() => _phase = _PagePhase.setup);
        return;
      }
      // play() completes when playback stops, so switch controls immediately.
      setState(() => _phase = _PagePhase.playing);
      await _player.play();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      await _stopAndWipe();
      if (mounted) setState(() => _phase = _PagePhase.setup);
    }
  }

  Future<void> _openArReader() async {
    final profile = ref.read(childProfileProvider).value;
    if (_arBusy ||
        _resourcesDisposed ||
        !_arSupported ||
        profile?.arEnabled != true ||
        profile?.id != _profileId ||
        _phase != _PagePhase.ready ||
        _page == null) {
      return;
    }
    final generation = _generation;
    final reader = ref.read(storyReaderProvider);
    final character = ref.read(selectedArCharacterProvider);
    var scanNext = false;
    var closed = false;
    setState(() => _arBusy = true);
    try {
      await _player.pause();
      if (!mounted || generation != _generation) return;
      final page = await _arAudio.prepare(_clips);
      if (!mounted || generation != _generation) return;
      final currentProfile = ref.read(childProfileProvider).value;
      if (currentProfile?.arEnabled != true ||
          currentProfile?.id != _profileId) {
        if (currentProfile?.id != _profileId) {
          await _stopAndWipe();
          if (mounted && generation == _generation) {
            setState(() => _phase = _PagePhase.setup);
          }
        } else {
          // The setting can change while native-compatible clips are copied.
          setState(() => _arBusy = false);
          await _listen();
        }
        return;
      }
      final result = await reader.open(
        pages: [page],
        initialPageIndex: 0,
        character: character,
        scannedPageMode: true,
      );
      scanNext = result.scanNextRequested;
      closed = !scanNext;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      final code = error is StoryReaderFailure
          ? error.code
          : error is ArNarrationFailure
              ? error.code
              : 'ar_failed';
      if (code == 'cancelled') {
        if (mounted) context.pop();
        return;
      }
      final s = AppLocalizations.of(context)!;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.arNotReadyTitle),
          content: Text(switch (code) {
            'ar_unsupported' => s.arErrUnsupported,
            'audio_missing' || 'audio_failed' => s.arErrAudio,
            'model_missing' || 'model_load_failed' => s.arErrModel,
            _ => s.arErrStart,
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.keepReading),
            ),
          ],
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _arBusy = false);
      }
    }
    if (!mounted || _resourcesDisposed || generation != _generation) return;
    if (scanNext) {
      // Android delivers the activity result before its host resumes. Wait for
      // Flutter's next visible frame before asking native to open the camera.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _resourcesDisposed || generation != _generation) return;
      await _scan();
    } else if (closed) {
      context.pop();
    } else {
      await _listen();
    }
  }

  Future<void> _replay() async {
    if (!mounted || _resourcesDisposed || _arBusy) return;
    final generation = _generation;
    setState(() => _phase = _PagePhase.playing);
    try {
      await _player.replay();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _phase = _PagePhase.failed);
      }
    }
  }

  Future<void> _stopAndWipe() async {
    await _player.stop();
    await _arAudio.dispose();
    await _clearClips();
    _page = null;
  }

  Future<void> _clearClips() async {
    for (final clip in _clips.toList()) {
      if (await clip.exists()) await clip.delete();
    }
    _clips.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final page = _page;
    if (_phase == _PagePhase.setup) {
      return ScanGrownUpHandoff(
        readyToRetry: false,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
        onPrimary: () => context.go(AppRoutes.onboarding),
        onPickStory: () => context.go(AppRoutes.home),
      );
    }
    final cameraFailure =
        _failureCode?.contains('camera_denied') == true ||
        _failureCode?.contains('camera_unavailable') == true;
    return Scaffold(
      appBar: AppBar(title: Text(s.scanTitle)),
      body: SafeArea(
        child: Center(
          child: switch (_phase) {
            _PagePhase.scanning => ScanChildState(
              icon: Icons.document_scanner_rounded,
              title: s.scanOpeningCamera,
              body: s.scanFindPage,
              loading: true,
            ),
            _PagePhase.preparing => ScanChildState(
              icon: Icons.auto_stories_rounded,
              title: s.speakablePreparing,
              body: s.scanPreparingBody,
              loading: true,
            ),
            _PagePhase.blocked => ScanChildState(
              icon: Icons.menu_book_rounded,
              title: s.scanTryAnotherTitle,
              body: s.scanTryAnotherBody,
              primaryLabel: s.scanAnotherPage,
              onPrimary: _scan,
              secondaryLabel: s.scanPickStoryInstead,
              onSecondary: () => context.go(AppRoutes.home),
            ),
            _PagePhase.failed => ScanChildState(
              icon: cameraFailure
                  ? Icons.camera_alt_outlined
                  : Icons.refresh_rounded,
              title: cameraFailure ? s.scanCameraHelpTitle : s.scanFailedTitle,
              body: cameraFailure ? s.scanCameraHelpBody : s.speakableFailed,
              primaryLabel: cameraFailure
                  ? s.scanPickStoryInstead
                  : s.tryScannerAgain,
              onPrimary: cameraFailure
                  ? () => context.go(AppRoutes.home)
                  : _scan,
              secondaryLabel: cameraFailure
                  ? s.tryScannerAgain
                  : s.scanPickStoryInstead,
              onSecondary: cameraFailure
                  ? _scan
                  : () => context.go(AppRoutes.home),
            ),
            _ =>
              page == null
                  ? ScanChildState(
                      icon: Icons.auto_stories_rounded,
                      title: s.speakablePreparing,
                      body: s.scanPreparingBody,
                      loading: true,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: PageImageView(
                                page: page,
                                activeLine: _player.currentLine,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_phase == _PagePhase.ready || _arBusy)
                            const CircularProgressIndicator()
                          else
                            ValueListenableBuilder<bool>(
                              valueListenable: _player.completed,
                              builder: (context, completed, _) {
                                if (completed) {
                                  return FilledButton.icon(
                                    onPressed: _replay,
                                    icon: const Icon(Icons.replay),
                                    label: Text(s.replayPage),
                                  );
                                }
                                return Wrap(
                                  spacing: 12,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () async {
                                        if (_phase == _PagePhase.playing) {
                                          await _player.pause();
                                          if (!mounted || _resourcesDisposed) {
                                            return;
                                          }
                                          setState(
                                            () => _phase = _PagePhase.paused,
                                          );
                                        } else {
                                          setState(
                                            () => _phase = _PagePhase.playing,
                                          );
                                          await _player.resume();
                                        }
                                      },
                                      icon: Icon(
                                        _phase == _PagePhase.playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        _phase == _PagePhase.playing
                                            ? s.speakablePause
                                            : s.speakableResume,
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _replay,
                                      icon: const Icon(Icons.replay),
                                      label: Text(s.replayPage),
                                    ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _arBusy ? null : _scan,
                            child: Text(s.scanAnotherPage),
                          ),
                        ],
                      ),
                    ),
          },
        ),
      ),
    );
  }
}
