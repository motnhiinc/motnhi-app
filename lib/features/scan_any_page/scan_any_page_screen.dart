import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import 'scan_any_page_controller.dart';

class ScanAnyPageScreen extends ConsumerStatefulWidget {
  const ScanAnyPageScreen({super.key});

  @override
  ConsumerState<ScanAnyPageScreen> createState() => _ScanAnyPageScreenState();
}

class _ScanAnyPageScreenState extends ConsumerState<ScanAnyPageScreen> {
  static const _maximumTextLength = 4000;

  final _flowId = Object();
  final _textController = TextEditingController();
  bool _manualEntry = false;

  ScanAnyPageDependencies get _dependencies => (
        scanService: ref.watch(scanServiceProvider),
        characterReader: ref.watch(characterReaderProvider),
        ttsClient: ref.watch(ttsClientProvider(_flowId)),
      );

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = scanAnyPageControllerProvider(_dependencies);
    final state = ref.watch(provider);

    ref.listen(provider, (previous, next) {
      if (next.phase == ScanAnyPagePhase.reviewingText &&
          previous?.recognizedText != next.recognizedText) {
        _textController.text = next.recognizedText;
        _manualEntry = false;
      }
      if (next.phase == ScanAnyPagePhase.idle &&
          previous?.phase != ScanAnyPagePhase.idle) {
        _textController.clear();
        _manualEntry = false;
      }
    });

    final controller = ref.read(provider.notifier);
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.scanTitle)),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _bodyFor(state, controller),
        ),
      ),
    );
  }

  Widget _bodyFor(
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final s = AppLocalizations.of(context)!;
    if (_manualEntry || state.phase == ScanAnyPagePhase.reviewingText) {
      return _review(controller);
    }

    switch (state.phase) {
      case ScanAnyPagePhase.idle:
        return _entry(controller);
      case ScanAnyPagePhase.scanning:
        return _ProgressState(
          key: const ValueKey('scanning'),
          icon: Icons.document_scanner_rounded,
          title: s.scanningTitle,
          message: s.scanningBody,
        );
      case ScanAnyPagePhase.generatingAudio:
        return _ProgressState(
          key: const ValueKey('generatingAudio'),
          icon: Icons.graphic_eq_rounded,
          title: s.generatingAudioTitle,
          message: s.generatingAudioBody,
        );
      case ScanAnyPagePhase.readyForAr:
        return _readyForAr(controller);
      case ScanAnyPagePhase.openingAr:
        return _ProgressState(
          key: const ValueKey('openingAr'),
          icon: Icons.view_in_ar_rounded,
          title: s.openingArTitle,
          message: s.openingArBody,
        );
      case ScanAnyPagePhase.failure:
        return _failure(state, controller);
      case ScanAnyPagePhase.reviewingText:
        throw StateError('Reviewing text is handled before the switch.');
    }
  }

  Widget _entry(ScanAnyPageController controller) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    Widget step({required String label, required bool active}) => Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? t.coral : t.line,
              ),
            ),
            const SizedBox(height: 6),
            EyebrowLabel(
              label,
              color: active ? t.coralDeep : t.inkMuted,
            ),
          ],
        );

    return _PageContent(
      key: const ValueKey('entry'),
      children: [
        const Spacer(),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    t.lavender.withValues(alpha: .18),
                    t.sageContainer.withValues(alpha: .25),
                    Colors.transparent,
                  ],
                  stops: const [0, .6, 1],
                ),
              ),
            ),
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.line, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.auto_stories_rounded,
                  size: 84, color: t.lavender),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text(
          s.scanHeroTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          s.scanHeroBody,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.inkMuted),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            step(label: s.stepScan, active: true),
            _StepLink(active: true),
            step(label: s.stepVoice, active: false),
            _StepLink(active: false),
            step(label: s.stepCharacter, active: false),
          ],
        ),
        const Spacer(),
        PressablePillButton(
          label: s.scanPrimaryCta,
          icon: Icons.document_scanner_rounded,
          onPressed: () => _startScan(controller),
        ),
        const SizedBox(height: 10),
        PressablePillButton(
          label: s.scanManualCta,
          variant: PillVariant.secondary,
          height: 46,
          onPressed: () => setState(() => _manualEntry = true),
        ),
        const SizedBox(height: 14),
        Text(
          s.scanOfflineNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _review(ScanAnyPageController controller) {
    final s = AppLocalizations.of(context)!;
    final count = _textController.text.runes.length;
    final overLimit = count > _maximumTextLength;
    final empty = _textController.text.trim().isEmpty;
    final colors = Theme.of(context).colorScheme;

    return _PageContent(
      key: const ValueKey('review'),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            s.scanLanguages,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.reviewTextTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(s.reviewTextBody),
        const SizedBox(height: 20),
        TextField(
          controller: _textController,
          minLines: 8,
          maxLines: null,
          autofocus: _manualEntry,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: s.reviewTextHint,
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          s.charCounter(count),
          textAlign: TextAlign.right,
          style: TextStyle(color: overLimit ? colors.error : null),
        ),
        if (overLimit)
          Text(
            s.charTooLong,
            style: TextStyle(color: colors.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: empty || overLimit
              ? null
              : () => controller.confirmText(_textController.text),
          child: Text(s.useThisText),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => _startScan(controller),
          child: Text(s.scanAgain),
        ),
      ],
    );
  }

  Widget _readyForAr(ScanAnyPageController controller) {
    final s = AppLocalizations.of(context)!;
    return _PageContent(
      key: const ValueKey('readyForAr'),
      children: [
        const Spacer(),
        Icon(
          Icons.record_voice_over_rounded,
          size: 112,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 32),
        Text(
          s.readyForArTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          s.readyForArBody,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: controller.openCharacterReader,
          icon: const Icon(Icons.view_in_ar_rounded),
          label: Text(s.placeCharacter),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: controller.reset,
          child: Text(s.scanAnotherPage),
        ),
      ],
    );
  }

  Widget _failure(
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final code = state.failureCode ?? '';
    if (code.startsWith('ar:')) {
      return _arFailure(code.substring(3), state, controller);
    }
    if (code.startsWith('tts:') && code != 'tts:invalid_text') {
      return _ttsFailure(code.substring(4), state, controller);
    }
    if (code == 'tts:invalid_text') {
      final s = AppLocalizations.of(context)!;
      return _FailureState(
        key: const ValueKey('textFailure'),
        icon: Icons.text_fields_rounded,
        title: s.textLengthTitle,
        message: s.textLengthBody,
        primaryLabel: s.editText,
        onPrimary: () => setState(() => _manualEntry = true),
        secondaryLabel: s.scanAnotherPage,
        onSecondary: controller.reset,
      );
    }

    return _scanFailure(
        code.startsWith('scan:') ? code.substring(5) : code, state, controller);
  }

  Widget _scanFailure(
    String code,
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final s = AppLocalizations.of(context)!;
    late final IconData icon;
    late final String title;
    late final String message;
    late final String primaryLabel;

    switch (code) {
      case 'camera_denied':
        icon = Icons.no_photography_rounded;
        title = s.scanErrCameraDeniedTitle;
        message = s.scanErrCameraDeniedBody;
        primaryLabel = s.tryCameraAgain;
      case 'camera_unavailable':
        icon = Icons.tablet_mac_rounded;
        title = s.scanErrCameraUnavailableTitle;
        message = s.scanErrCameraUnavailableBody;
        primaryLabel = s.tryScannerAgain;
      case 'page_not_found':
      case 'rectangle_not_found':
      case 'unstable_page':
        icon = Icons.crop_free_rounded;
        title = s.scanErrNoPageTitle;
        message = s.scanErrNoPageBody;
        primaryLabel = s.scanAgain;
      case 'capture_failed':
        icon = Icons.camera_alt_outlined;
        title = s.scanErrCaptureTitle;
        message = s.scanErrCaptureBody;
        primaryLabel = s.scanAgain;
      case 'correction_failed':
        icon = Icons.crop_rotate_rounded;
        title = s.scanErrCorrectionTitle;
        message = s.scanErrCorrectionBody;
        primaryLabel = s.scanAgain;
      case 'ocr_failed':
        icon = Icons.text_snippet_outlined;
        title = s.scanErrOcrTitle;
        message = s.scanErrOcrBody;
        primaryLabel = s.scanAgain;
      case 'no_text':
        icon = Icons.text_fields_rounded;
        title = s.scanErrNoTextTitle;
        message = s.scanErrNoTextBody;
        primaryLabel = s.scanAgain;
      default:
        icon = Icons.error_outline_rounded;
        title = s.scanErrGenericTitle;
        message = s.scanErrGenericBody;
        primaryLabel = s.tryScannerAgain;
    }

    return _FailureState(
      key: const ValueKey('scanFailure'),
      icon: icon,
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      onPrimary: () => _startScan(controller),
      secondaryLabel: s.enterTextManually,
      onSecondary: () {
        _textController.text = state.confirmedText;
        setState(() => _manualEntry = true);
      },
    );
  }

  Widget _ttsFailure(
    String code,
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final s = AppLocalizations.of(context)!;
    final count = _textController.text.runes.length;
    final overLimit = count > _maximumTextLength;
    final canRetry = _textController.text.trim().isNotEmpty && !overLimit;
    final colors = Theme.of(context).colorScheme;
    late final IconData icon;
    late final String title;
    late final String message;

    switch (code) {
      case 'backend_unreachable':
      case 'network':
      case 'connection_error':
        icon = Icons.wifi_off_rounded;
        title = s.ttsErrNetworkTitle;
        message = s.ttsErrNetworkBody;
      case 'auth':
      case 'auth_failed':
      case 'authentication':
      case 'authentication_failed':
      case 'unauthorized':
        icon = Icons.lock_outline_rounded;
        title = s.ttsErrAuthTitle;
        message = s.ttsErrAuthBody;
      case 'rate_limit':
      case 'rate_limited':
        icon = Icons.hourglass_top_rounded;
        title = s.ttsErrRateTitle;
        message = s.ttsErrRateBody;
      case 'timeout':
      case 'timed_out':
        icon = Icons.timer_outlined;
        title = s.ttsErrTimeoutTitle;
        message = s.ttsErrTimeoutBody;
      case 'invalid_audio':
        icon = Icons.audio_file_outlined;
        title = s.ttsErrInvalidAudioTitle;
        message = s.ttsErrInvalidAudioBody;
      default:
        icon = Icons.record_voice_over_outlined;
        title = s.ttsErrGenericTitle;
        message = s.ttsErrGenericBody;
    }

    return _PageContent(
      key: const ValueKey('ttsFailure'),
      children: [
        Icon(
          icon,
          size: 88,
          color: colors.error,
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _textController,
          minLines: 6,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          s.charCounter(count),
          textAlign: TextAlign.right,
          style: TextStyle(color: overLimit ? colors.error : null),
        ),
        if (overLimit)
          Text(
            s.charTooLong,
            style: TextStyle(color: colors.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: canRetry
              ? () {
                  final text = _textController.text.trim();
                  if (text == state.confirmedText) {
                    controller.retryTts();
                  } else {
                    controller.confirmText(text);
                  }
                }
              : null,
          child: Text(s.tryNarrationAgain),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: controller.reset,
          child: Text(s.scanAnotherPage),
        ),
      ],
    );
  }

  Widget _arFailure(
    String code,
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final s = AppLocalizations.of(context)!;
    late final IconData icon;
    late final String title;
    late final String message;
    var primaryLabel = s.tryArAgain;
    VoidCallback onPrimary = controller.openCharacterReader;
    var secondaryLabel = s.scanAnotherPage;
    VoidCallback onSecondary = controller.reset;

    switch (code) {
      case 'ar_unsupported':
        icon = Icons.tablet_mac_rounded;
        title = s.scanArErrUnsupportedTitle;
        message = s.scanArErrUnsupportedBody;
        primaryLabel = s.scanAnotherPage;
        onPrimary = controller.reset;
        secondaryLabel = s.closeLabel;
        onSecondary = () => Navigator.of(context).maybePop();
      case 'ar_unavailable':
        icon = Icons.tablet_mac_rounded;
        title = s.scanArErrUnavailableTitle;
        message = s.scanArErrUnavailableBody;
      case 'ar_failed':
        icon = Icons.view_in_ar_outlined;
        title = s.scanArErrFailedTitle;
        message = s.scanArErrFailedBody;
      case 'surface_not_found':
      case 'plane_not_found':
        icon = Icons.table_restaurant_outlined;
        title = s.scanArErrSurfaceTitle;
        message = s.scanArErrSurfaceBody;
      case 'model_missing':
        icon = Icons.smart_toy_outlined;
        title = s.scanArErrModelMissingTitle;
        message = s.scanArErrModelMissingBody;
        primaryLabel = s.scanAnotherPage;
        onPrimary = controller.reset;
        secondaryLabel = s.closeLabel;
        onSecondary = () => Navigator.of(context).maybePop();
      case 'model_load_failed':
        icon = Icons.smart_toy_outlined;
        title = s.scanArErrModelLoadTitle;
        message = s.scanArErrModelLoadBody;
        primaryLabel = s.scanAnotherPage;
        onPrimary = controller.reset;
        secondaryLabel = s.closeLabel;
        onSecondary = () => Navigator.of(context).maybePop();
      case 'audio_missing':
      case 'missing_audio':
        icon = Icons.audio_file_outlined;
        title = s.scanArErrAudioMissingTitle;
        message = s.scanArErrAudioMissingBody;
        primaryLabel = s.createVoiceAgain;
        onPrimary = () => controller.confirmText(state.confirmedText);
      case 'audio_failed':
        icon = Icons.volume_off_outlined;
        title = s.scanArErrAudioFailedTitle;
        message = s.scanArErrAudioFailedBody;
        primaryLabel = s.scanAnotherPage;
        onPrimary = controller.reset;
        secondaryLabel = s.closeLabel;
        onSecondary = () => Navigator.of(context).maybePop();
      default:
        icon = Icons.view_in_ar_outlined;
        title = s.scanArErrGenericTitle;
        message = s.scanArErrGenericBody;
    }

    return _FailureState(
      key: const ValueKey('arFailure'),
      icon: icon,
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
    );
  }

  void _startScan(ScanAnyPageController controller) {
    setState(() => _manualEntry = false);
    controller.startScan();
  }
}

/// Dotted-line connector between the scan → voice → character stepper beads.
class _StepLink extends StatelessWidget {
  const _StepLink({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 2,
      margin: const EdgeInsets.only(top: 4),
      color: active ? context.stitch.coral : context.stitch.line,
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 24.0;
        final availableHeight = constraints.maxHeight - padding * 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(padding),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 680,
                minHeight: availableHeight > 0 ? availableHeight : 0,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressState extends StatelessWidget {
  const _ProgressState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _PageContent(
      children: [
        const Spacer(),
        Icon(icon, size: 88, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const Spacer(),
      ],
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return _PageContent(
      children: [
        const Spacer(),
        Icon(
          icon,
          size: 88,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const Spacer(),
        FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel)),
      ],
    );
  }
}
