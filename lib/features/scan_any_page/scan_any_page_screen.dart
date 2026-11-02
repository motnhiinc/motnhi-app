import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../profile/profile_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../ar/ar_character.dart';
import '../ar/ar_diagnostics_disclosure.dart';
import '../ar/ar_reader_diagnostic.dart';
import '../ar/native_story_reader.dart';
import 'scan_child_states.dart';
import 'line_audio_player.dart';
import 'page_image_view.dart';
import 'page_validation_client.dart';
import 'scan_page_coordinator.dart';

class ScanAnyPageScreen extends ConsumerStatefulWidget {
  const ScanAnyPageScreen({super.key, this.coordinator});

  /// An already prepared session transfers lifecycle ownership to this screen.
  final ScanPageCoordinator? coordinator;
  @override
  ConsumerState<ScanAnyPageScreen> createState() => _ScanAnyPageScreenState();
}

class _ScanAnyPageScreenState extends ConsumerState<ScanAnyPageScreen>
    with WidgetsBindingObserver {
  late final ScanPageCoordinator _session;
  late final List<Future<void> Function()> _liveDisposers;
  late final Future<void> Function() _disposeResources;
  String _language = Platform.isAndroid ? 'vi' : 'en';
  int _scanGeneration = 0;
  StoryReaderSupport? _arSupport;
  bool _arOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session =
        widget.coordinator ??
              ScanPageCoordinator(
                scanner: ref.read(scanServiceProvider),
                client: PageValidationClient(
                  ref.read(apiClientProvider),
                  onExtraction: (elapsed) => _session.recordExtraction(elapsed),
                ),
                player: LineAudioPlayer(
                  onFirstPlaybackProgress: () =>
                      _session.recordFirstPlaybackProgress(),
                ),
                onCancelled: () {
                  if (mounted) context.pop();
                },
                diagnostic: (event) => debugPrint('ScanStages $event'),
              )
          ..bindPlayback();
    _session.addListener(_changed);
    unawaited(_checkArSupport());
    _liveDisposers = ref.read(liveResourceDisposersProvider);
    _disposeResources = () async {
      _scanGeneration++;
      await _session.close();
    };
    _liveDisposers.add(_disposeResources);
    if (widget.coordinator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initialScan());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.setForeground(state == AppLifecycleState.resumed);
  }

  Future<void> _checkArSupport() async {
    StoryReaderSupport support;
    try {
      support = await ref.read(storyReaderProvider).isSupported();
    } catch (_) {
      support = const StoryReaderSupport(supported: false);
    }
    if (mounted) setState(() => _arSupport = support);
  }

  Future<void> _openAr() async {
    if (_arOpening ||
        !_session.canOpenAr ||
        !(ref.read(childProfileProvider).value?.arEnabled ?? false)) {
      return;
    }
    setState(() => _arOpening = true);
    final generation = _scanGeneration;
    try {
      if (_session.phase == ScanPagePhase.playing) await _session.pause();
      if (!mounted || generation != _scanGeneration) return;
      if (!_session.canOpenAr ||
          !(ref.read(childProfileProvider).value?.arEnabled ?? false)) {
        return;
      }
      await _session.openAr(
        reader: ref.read(storyReaderProvider),
        character: dinosaurCharacter,
        temporaryDirectory: () async =>
            ref.read(ttsTemporaryDirectoryProvider)?.call() ??
            await getTemporaryDirectory(),
      );
    } on StoryReaderFailure catch (error) {
      if (mounted && generation == _scanGeneration) {
        await _showArFailure(error.code, diagnostic: error.diagnostic);
      }
    } catch (_) {
      if (mounted && generation == _scanGeneration) {
        await _showArFailure('ar_failed');
      }
    } finally {
      if (mounted) setState(() => _arOpening = false);
    }
  }

  Future<void> _showArFailure(
    String code, {
    ArReaderDiagnostic? diagnostic,
  }) async {
    final s = AppLocalizations.of(context)!;
    final message = switch (code) {
      'ar_unsupported' => s.arErrUnsupported,
      'audio_missing' || 'audio_failed' => s.arErrAudio,
      'model_missing' || 'model_load_failed' => s.arErrModel,
      'ar_failed' || 'ar_unavailable' => s.arErrStart,
      _ => s.arErrGeneric,
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.arNotReadyTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (diagnostic != null)
              ArDiagnosticsDisclosure(diagnostic: diagnostic),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.keepReading),
          ),
        ],
      ),
    );
  }

  Future<void> _initialScan() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final selected = preferences.getString('scan_content_language');
    if (selected == 'vi' || selected == 'en') _language = selected!;
    await _scan();
  }

  Future<void> _scan() async {
    if (_arOpening) return;
    final generation = ++_scanGeneration;
    try {
      final profile = await ref.read(childProfileProvider.future);
      if (!mounted || generation != _scanGeneration) return;
      if (_arSupport == null) await _checkArSupport();
      if (!mounted || generation != _scanGeneration) return;
      final reader = ref.read(storyReaderProvider);
      final useAr =
          profile?.arEnabled == true &&
          _arSupport?.supported == true &&
          reader is PreparingStoryReader;
      await _session.scan(
        profile?.id,
        language: _language,
        automaticAr: useAr
            ? ScanArEntry(
                reader: reader as PreparingStoryReader,
                character: dinosaurCharacter,
                onScanNextPage: () {
                  if (mounted) unawaited(_scan());
                },
                temporaryDirectory: () async =>
                    ref.read(ttsTemporaryDirectoryProvider)?.call() ??
                    await getTemporaryDirectory(),
              )
            : null,
        autoplayWithoutAr: true,
      );
    } catch (_) {
      if (mounted && generation == _scanGeneration) await _session.scan(null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final arEnabled = ref.watch(childProfileProvider).value?.arEnabled ?? false;
    final hasNarration = {
      ScanPagePhase.ready,
      ScanPagePhase.playing,
      ScanPagePhase.paused,
      ScanPagePhase.completed,
    }.contains(phase);
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
            enabled:
                !_arOpening &&
                {
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
                          if (hasNarration && _session.arFailure != null) ...[
                            Text(s.arErrStart, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                          ],
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
                              onPressed: _arOpening ? null : _session.listen,
                            )
                          else if (phase == ScanPagePhase.completed)
                            FilledButton.icon(
                              onPressed: _arOpening ? null : _session.replay,
                              icon: const Icon(Icons.replay),
                              label: Text(s.replayPage),
                            )
                          else
                            Wrap(
                              spacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _arOpening
                                      ? null
                                      : phase == ScanPagePhase.playing
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
                                  onPressed: _arOpening
                                      ? null
                                      : _session.replay,
                                  icon: const Icon(Icons.replay),
                                  label: Text(s.replayPage),
                                ),
                              ],
                            ),
                          if (hasNarration &&
                              arEnabled &&
                              _arSupport?.supported == true) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: const ValueKey('scan.seeInAr'),
                              onPressed: _arOpening ? null : _openAr,
                              icon: _session.arBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.view_in_ar_rounded),
                              label: Text(
                                _session.arBusy ? s.arPrepOpening : s.seeInAr,
                              ),
                            ),
                          ],
                          if (hasNarration &&
                              arEnabled &&
                              _arSupport?.supported == false) ...[
                            const SizedBox(height: 12),
                            Text(
                              s.arErrUnsupported,
                              textAlign: TextAlign.center,
                            ),
                            if (_arSupport?.diagnostic != null)
                              ArDiagnosticsDisclosure(
                                diagnostic: _arSupport!.diagnostic!,
                              ),
                          ],
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _arOpening ? null : _scan,
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
