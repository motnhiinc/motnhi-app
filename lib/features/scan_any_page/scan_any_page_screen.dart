import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../profile/profile_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import 'scan_child_states.dart';
import 'line_audio_player.dart';
import 'page_image_view.dart';
import 'page_validation_client.dart';
import 'scan_page_coordinator.dart';

class ScanAnyPageScreen extends ConsumerStatefulWidget {
  const ScanAnyPageScreen({super.key});
  @override
  ConsumerState<ScanAnyPageScreen> createState() => _ScanAnyPageScreenState();
}

class _ScanAnyPageScreenState extends ConsumerState<ScanAnyPageScreen> {
  late final ScanPageCoordinator _session;
  late final List<Future<void> Function()> _liveDisposers;
  late final Future<void> Function() _disposeResources;
  String _language = Platform.isAndroid ? 'vi' : 'en';
  int _scanGeneration = 0;

  @override
  void initState() {
    super.initState();
    _session = ScanPageCoordinator(
      scanner: ref.read(scanServiceProvider),
      client: PageValidationClient(
        ref.read(apiClientProvider),
        onExtraction: (elapsed) => _session.recordExtraction(elapsed),
      ),
      player: LineAudioPlayer(
        onFirstPlaybackProgress: () => _session.recordFirstPlaybackProgress(),
      ),
      onCancelled: () {
        if (mounted) context.pop();
      },
      diagnostic: (event) => debugPrint('ScanStages $event'),
    )..bindPlayback();
    _session.addListener(_changed);
    _liveDisposers = ref.read(liveResourceDisposersProvider);
    _disposeResources = () async {
      _scanGeneration++;
      await _session.close();
    };
    _liveDisposers.add(_disposeResources);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScan());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialScan() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final selected = preferences.getString('scan_content_language');
    if (selected == 'vi' || selected == 'en') _language = selected!;
    await _scan();
  }

  Future<void> _scan() async {
    final generation = ++_scanGeneration;
    try {
      final profile = await ref.read(childProfileProvider.future);
      if (!mounted || generation != _scanGeneration) return;
      await _session.scan(profile?.id, language: _language);
    } catch (_) {
      if (mounted && generation == _scanGeneration) await _session.scan(null);
    }
  }

  @override
  void dispose() {
    _scanGeneration++;
    _session.removeListener(_changed);
    _liveDisposers.remove(_disposeResources);
    unawaited(_disposeResources());
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final phase = _session.phase;
    final page = _session.page;
    final cameraFailure = {
      'camera_denied',
      'camera_unavailable',
      'scanner_initialization_timeout',
    }.contains(_session.reason);
    final retryStage =
        _session.recovery == ScanRecovery.validation ||
        _session.recovery == ScanRecovery.audio;
    final failureBody = switch (_session.reason) {
      'no_text' => s.scanNoTextGuidance,
      'image_quality_low' => s.scanBlurGuidance,
      'page_too_long' => s.scanPageTooLong,
      'text_mismatch' || 'recognition_uncertain' => s.scanRecognitionGuidance,
      'page_approval_expired' => s.scanApprovalExpired,
      'page_approval_invalid' => s.scanApprovalInvalid,
      'image_decode_failed' ||
      'image_encode_failed' => s.scanImageProcessingFailed,
      'ocr_failed' => s.scanRecognitionFailed,
      'provider_timeout' ||
      'provider_capacity' ||
      'provider_unavailable' ||
      'network_unavailable' => s.scanServiceRetry,
      _ => s.scanProcessingFailed,
    };
    if (phase == ScanPagePhase.setup) {
      return ScanGrownUpHandoff(
        readyToRetry: false,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
        onPrimary: () => context.go(AppRoutes.onboarding),
        onHome: () => context.go(AppRoutes.home),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.scanTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: s.scanContentLanguage,
            enabled: {
              ScanPagePhase.ready,
              ScanPagePhase.failed,
              ScanPagePhase.blocked,
              ScanPagePhase.completed,
            }.contains(phase),
            onSelected: (language) async {
              // A language change starts a NEW session, never mutates approval.
              _language = language;
              final preferences = await SharedPreferences.getInstance();
              await preferences.setString('scan_content_language', language);
              if (mounted) await _scan();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'vi', child: Text('Tiếng Việt')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_language.toUpperCase()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: switch (phase) {
            ScanPagePhase.scanning => ScanChildState(
              icon: Icons.document_scanner_rounded,
              title: s.scanOpeningCamera,
              body: s.scanFindPage,
              loading: true,
            ),
            ScanPagePhase.validating => ScanChildState(
              icon: Icons.auto_stories_rounded,
              title: s.scanValidating,
              body: s.scanPreparingBody,
              loading: true,
            ),
            ScanPagePhase.blocked => ScanChildState(
              icon: Icons.menu_book_rounded,
              title: s.scanTryAnotherTitle,
              body: _session.recovery == ScanRecovery.retake
                  ? failureBody
                  : s.scanTryAnotherBody,
              primaryLabel: s.scanAnotherPage,
              onPrimary: _scan,
              secondaryLabel: s.scanBackHome,
              onSecondary: () => context.go(AppRoutes.home),
            ),
            ScanPagePhase.failed => ScanChildState(
              icon: cameraFailure
                  ? Icons.camera_alt_outlined
                  : Icons.refresh_rounded,
              title: cameraFailure ? s.scanCameraHelpTitle : s.scanFailedTitle,
              body: cameraFailure ? s.scanCameraHelpBody : failureBody,
              primaryLabel: cameraFailure
                  ? s.scanBackHome
                  : retryStage
                  ? s.scanRetryStage
                  : s.tryScannerAgain,
              onPrimary: cameraFailure
                  ? () => context.go(AppRoutes.home)
                  : retryStage
                  ? _session.retry
                  : _scan,
              secondaryLabel: cameraFailure
                  ? s.tryScannerAgain
                  : s.scanBackHome,
              onSecondary: cameraFailure
                  ? _scan
                  : () => context.go(AppRoutes.home),
            ),
            _ =>
              page == null
                  ? ScanChildState(
                      icon: Icons.auto_stories_rounded,
                      title: s.scanPreparingAudio,
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
                                activeLine: _session.player.currentLine,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (phase == ScanPagePhase.preparingAudio) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(s.scanPreparingAudio),
                            FilledButton(
                              onPressed: null,
                              child: Text(s.speakableListen),
                            ),
                          ] else if (phase == ScanPagePhase.ready)
                            PressablePillButton(
                              label: s.speakableListen,
                              icon: Icons.volume_up_rounded,
                              height: 64,
                              onPressed: _session.listen,
                            )
                          else if (phase == ScanPagePhase.completed)
                            FilledButton.icon(
                              onPressed: _session.replay,
                              icon: const Icon(Icons.replay),
                              label: Text(s.replayPage),
                            )
                          else
                            Wrap(
                              spacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: phase == ScanPagePhase.playing
                                      ? _session.pause
                                      : _session.resume,
                                  icon: Icon(
                                    phase == ScanPagePhase.playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                  label: Text(
                                    phase == ScanPagePhase.playing
                                        ? s.speakablePause
                                        : s.speakableResume,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _session.replay,
                                  icon: const Icon(Icons.replay),
                                  label: Text(s.replayPage),
                                ),
                              ],
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
