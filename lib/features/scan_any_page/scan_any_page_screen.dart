import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../features/profile/profile_providers.dart';
import '../../features/privacy/privacy_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import 'scan_child_states.dart';
import 'line_audio_player.dart';
import 'native_scan_service.dart';
import 'page_image_view.dart';
import 'page_validation_client.dart';
import 'scanned_page.dart';

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

class _ScanAnyPageScreenState extends ConsumerState<ScanAnyPageScreen>
    with WidgetsBindingObserver {
  late final PageValidationClient _client;
  late final LineAudioPlayer _player;
  late final List<Future<void> Function()> _liveDisposers;
  late final Future<void> Function() _disposeResources;
  final List<File> _clips = [];
  ScannedPage? _page;
  String? _profileId;
  _PagePhase _phase = _PagePhase.scanning;
  int _generation = 0;
  Timer? _consentTimer;
  bool _checkingConsent = false;
  String? _failureCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = PageValidationClient(
      ref.read(apiClientProvider),
      hasEffectiveConsent: () =>
          ref.read(effectiveCloudTtsProvider) &&
          ref.read(effectivePageImageValidationProvider),
    );
    _player = LineAudioPlayer();
    _liveDisposers = ref.read(liveResourceDisposersProvider);
    _disposeResources = () async {
      await _client.dispose();
      await _player.dispose();
    };
    _liveDisposers.add(_disposeResources);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _generation++;
    _consentTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _liveDisposers.remove(_disposeResources);
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _scan() async {
    final generation = ++_generation;
    setState(() {
      _phase = _PagePhase.scanning;
      _page = null;
      _failureCode = null;
    });
    await _player.stop();
    await _clearClips();
    var step = 'consent';
    try {
      ref.invalidate(privacyProvider);
      final consent = await ref.read(privacyProvider.future);
      final profile = await ref.read(childProfileProvider.future);
      if (!mounted || generation != _generation) return;
      if (profile == null ||
          !consent.effectiveCloudTtsEnabled ||
          !consent.effectivePageImageValidationEnabled) {
        setState(() => _phase = _PagePhase.setup);
        return;
      }
      _profileId = profile.id;
      step = 'capture';
      final page = await ref.read(scanServiceProvider).scanAndRecognize();
      if (!mounted || generation != _generation) return;
      setState(() => _phase = _PagePhase.preparing);
      step = 'validation';
      final result = await _client.validate(page, profile.id);
      if (!mounted || generation != _generation) return;
      if (result.blocked || result.proof == null) {
        setState(() => _phase = _PagePhase.blocked);
        return;
      }
      step = 'audio';
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
      if (clips.length != page.lines.length ||
          page.lines.any((line) => !line.isValid)) {
        setState(() => _phase = _PagePhase.failed);
        return;
      }
      _clips.addAll(clips);
      await _player.load(clips);
      if (mounted && generation == _generation) {
        setState(() {
          _page = page;
          _phase = _PagePhase.ready;
        });
      }
    } on ScanCancelled {
      if (mounted && generation == _generation) context.pop();
    } catch (error) {
      if (mounted && generation == _generation) {
        final code = error is ScanFailure ? error.code : error.runtimeType;
        debugPrint('Scan Any Page failed at $step: $code');
        setState(() {
          _failureCode = '$step: $code';
          _phase = _PagePhase.failed;
        });
      }
    }
  }

  Future<void> _listen() async {
    final generation = _generation;
    try {
      ref.invalidate(privacyProvider);
      final consent = await ref.read(privacyProvider.future);
      if (!mounted || generation != _generation) return;
      if (!consent.effectiveCloudTtsEnabled ||
          !consent.effectivePageImageValidationEnabled ||
          _profileId == null) {
        await _stopAndWipe();
        if (mounted) setState(() => _phase = _PagePhase.setup);
        return;
      }
      await _player.play();
      if (mounted && generation == _generation) {
        setState(() => _phase = _PagePhase.playing);
        _startConsentMonitor();
      }
    } catch (_) {
      await _stopAndWipe();
      if (mounted) setState(() => _phase = _PagePhase.setup);
    }
  }

  Future<void> _stopAndWipe() async {
    _consentTimer?.cancel();
    _consentTimer = null;
    await _player.stop();
    await _clearClips();
    _page = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_phase == _PagePhase.playing || _phase == _PagePhase.paused)) {
      unawaited(_refreshActiveConsent());
    }
  }

  void _startConsentMonitor() {
    _consentTimer?.cancel();
    _consentTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshActiveConsent()),
    );
  }

  Future<void> _refreshActiveConsent() async {
    if (_checkingConsent || !mounted) return;
    _checkingConsent = true;
    try {
      ref.invalidate(privacyProvider);
      final consent = await ref.read(privacyProvider.future);
      if (!mounted) return;
      if (!consent.effectiveCloudTtsEnabled ||
          !consent.effectivePageImageValidationEnabled) {
        await _stopAndWipe();
        if (mounted) setState(() => _phase = _PagePhase.setup);
      }
    } catch (_) {
      await _stopAndWipe();
      if (mounted) setState(() => _phase = _PagePhase.setup);
    } finally {
      _checkingConsent = false;
    }
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
      final readyToRetry = ref.watch(effectiveCloudTtsProvider) &&
          ref.watch(effectivePageImageValidationProvider);
      return ScanGrownUpHandoff(
        readyToRetry: readyToRetry,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
        onPrimary:
            readyToRetry ? _scan : () => context.push(AppRoutes.parentPrivacy),
        onPickStory: () => context.go(AppRoutes.home),
      );
    }
    final cameraFailure = _failureCode?.contains('camera_denied') == true ||
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
                title:
                    cameraFailure ? s.scanCameraHelpTitle : s.scanFailedTitle,
                body: cameraFailure ? s.scanCameraHelpBody : s.speakableFailed,
                primaryLabel:
                    cameraFailure ? s.scanPickStoryInstead : s.tryScannerAgain,
                onPrimary:
                    cameraFailure ? () => context.go(AppRoutes.home) : _scan,
                secondaryLabel:
                    cameraFailure ? s.tryScannerAgain : s.scanPickStoryInstead,
                onSecondary:
                    cameraFailure ? _scan : () => context.go(AppRoutes.home),
              ),
            _ => page == null
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
                        if (_phase == _PagePhase.ready)
                          PressablePillButton(
                            label: s.speakableListen,
                            icon: Icons.volume_up_rounded,
                            height: 64,
                            onPressed: _listen,
                          )
                        else
                          ValueListenableBuilder<bool>(
                            valueListenable: _player.completed,
                            builder: (context, completed, _) {
                              if (completed) {
                                return FilledButton.icon(
                                  onPressed: () async {
                                    await _player.replay();
                                    setState(
                                      () => _phase = _PagePhase.playing,
                                    );
                                  },
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
                                        setState(
                                          () => _phase = _PagePhase.paused,
                                        );
                                      } else {
                                        await _player.resume();
                                        setState(
                                          () => _phase = _PagePhase.playing,
                                        );
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
                                    onPressed: () async {
                                      await _player.replay();
                                      setState(
                                        () => _phase = _PagePhase.playing,
                                      );
                                    },
                                    icon: const Icon(Icons.replay),
                                    label: Text(s.replayPage),
                                  ),
                                ],
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _scan,
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
