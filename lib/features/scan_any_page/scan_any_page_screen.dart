import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Scan any page')),
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
    if (_manualEntry || state.phase == ScanAnyPagePhase.reviewingText) {
      return _review(controller);
    }

    switch (state.phase) {
      case ScanAnyPagePhase.idle:
        return _entry(controller);
      case ScanAnyPagePhase.scanning:
        return const _ProgressState(
          key: ValueKey('scanning'),
          icon: Icons.document_scanner_rounded,
          title: 'Scanning your page…',
          message: 'Hold over one page and keep all four corners visible.',
        );
      case ScanAnyPagePhase.generatingAudio:
        return const _ProgressState(
          key: ValueKey('generatingAudio'),
          icon: Icons.graphic_eq_rounded,
          title: 'Giving your character a voice…',
          message: 'Keep the Mac and iPad on the same Wi-Fi. The OpenAI key '
              'stays on the backend and is never stored in this app.',
        );
      case ScanAnyPagePhase.readyForAr:
        return _readyForAr(controller);
      case ScanAnyPagePhase.openingAr:
        return const _ProgressState(
          key: ValueKey('openingAr'),
          icon: Icons.view_in_ar_rounded,
          title: 'Opening character reader…',
          message: 'Move the iPad slowly to find a flat surface.',
        );
      case ScanAnyPagePhase.failure:
        return _failure(state, controller);
      case ScanAnyPagePhase.reviewingText:
        throw StateError('Reviewing text is handled before the switch.');
    }
  }

  Widget _entry(ScanAnyPageController controller) {
    return _PageContent(
      key: const ValueKey('entry'),
      children: [
        const Spacer(),
        Icon(
          Icons.auto_stories_rounded,
          size: 112,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 32),
        Text(
          'Bring any story page to life',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Scan one page with large, clear text. A character will read it '
          'aloud from your table.',
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => _startScan(controller),
          icon: const Icon(Icons.document_scanner_rounded),
          label: const Text('Scan a page'),
        ),
      ],
    );
  }

  Widget _review(ScanAnyPageController controller) {
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
            'English + Vietnamese',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Check the words before reading',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Tap in the text to correct recognition mistakes.'),
        const SizedBox(height: 20),
        TextField(
          controller: _textController,
          minLines: 8,
          maxLines: null,
          autofocus: _manualEntry,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter the words on the page',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          '$count / 4,000 characters',
          textAlign: TextAlign.right,
          style: TextStyle(color: overLimit ? colors.error : null),
        ),
        if (overLimit)
          Text(
            'Shorten the text to 4,000 characters or fewer.',
            style: TextStyle(color: colors.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: empty || overLimit
              ? null
              : () => controller.confirmText(_textController.text),
          child: const Text('Use this text'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => _startScan(controller),
          child: const Text('Scan again'),
        ),
      ],
    );
  }

  Widget _readyForAr(ScanAnyPageController controller) {
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
          'Your character is ready',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Find a table or another flat surface, then place your reader.',
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: controller.openCharacterReader,
          icon: const Icon(Icons.view_in_ar_rounded),
          label: const Text('Place character'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: controller.reset,
          child: const Text('Scan another page'),
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
      return _FailureState(
        key: const ValueKey('textFailure'),
        icon: Icons.text_fields_rounded,
        title: 'Check the text length',
        message:
            'Enter between 1 and 4,000 characters before creating the voice.',
        primaryLabel: 'Edit text',
        onPrimary: () => setState(() => _manualEntry = true),
        secondaryLabel: 'Scan another page',
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
    late final IconData icon;
    late final String title;
    late final String message;
    late final String primaryLabel;

    switch (code) {
      case 'camera_denied':
        icon = Icons.no_photography_rounded;
        title = 'Camera access is off';
        message = 'Camera access is required to scan a page. Allow camera '
            'access in iPad Settings, then return and try again.';
        primaryLabel = 'Try camera again';
      case 'camera_unavailable':
        icon = Icons.tablet_mac_rounded;
        title = 'The scanner is not available';
        message = 'This demo requires a supported physical iPad with an '
            'available camera.';
        primaryLabel = 'Try scanner again';
      case 'page_not_found':
      case 'rectangle_not_found':
      case 'unstable_page':
        icon = Icons.crop_free_rounded;
        title = "We couldn't find one clear page";
        message =
            'Place one flat page in good light, avoid glare, and keep all '
            'four corners visible.';
        primaryLabel = 'Scan again';
      case 'capture_failed':
        icon = Icons.camera_alt_outlined;
        title = "We couldn't capture the page";
        message = 'Hold the iPad steady over one well-lit page and keep all '
            'four corners in view.';
        primaryLabel = 'Scan again';
      case 'correction_failed':
        icon = Icons.crop_rotate_rounded;
        title = "We couldn't straighten the page";
        message = 'Lay the page flat, reduce glare, and scan with all four '
            'corners clearly visible.';
        primaryLabel = 'Scan again';
      case 'ocr_failed':
        icon = Icons.text_snippet_outlined;
        title = "We couldn't recognize the words";
        message = 'Try a flat, well-lit page with large, clear English or '
            'Vietnamese text.';
        primaryLabel = 'Scan again';
      case 'no_text':
        icon = Icons.text_fields_rounded;
        title = "We couldn't read enough text";
        message = 'Try a page with large, clear English or Vietnamese text, or '
            'enter the words yourself.';
        primaryLabel = 'Scan again';
      default:
        icon = Icons.error_outline_rounded;
        title = 'Scanning stopped';
        message = 'The scanner could not finish this page. Try again or enter '
            'the words yourself.';
        primaryLabel = 'Try scanner again';
    }

    return _FailureState(
      key: const ValueKey('scanFailure'),
      icon: icon,
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      onPrimary: () => _startScan(controller),
      secondaryLabel: 'Enter text manually',
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
        title = "We couldn't reach the narration service";
        message = 'Make sure the Mac backend is running and the Mac and iPad '
            'are on the same Wi-Fi, then try again.';
      case 'auth':
      case 'auth_failed':
      case 'authentication':
      case 'authentication_failed':
      case 'unauthorized':
        icon = Icons.lock_outline_rounded;
        title = "We couldn't verify this iPad";
        message = 'The app could not renew access to the narration service. '
            'Your text is still here; try again.';
      case 'rate_limit':
      case 'rate_limited':
        icon = Icons.hourglass_top_rounded;
        title = 'The narration service is busy';
        message = 'Wait a moment before trying again. Your text is still here '
            'and can be edited.';
      case 'timeout':
      case 'timed_out':
        icon = Icons.timer_outlined;
        title = 'The voice took too long to create';
        message = 'The narration request timed out. Your text is still here; '
            'try again when the connection is stable.';
      case 'invalid_audio':
        icon = Icons.audio_file_outlined;
        title = "We couldn't use the voice response";
        message = 'The narration service did not return usable audio. No audio '
            'was saved; your text is still here.';
      default:
        icon = Icons.record_voice_over_outlined;
        title = "We couldn't create the voice";
        message = 'The narration service could not finish this request. Your '
            'text is still here and can be edited before trying again.';
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
          '$count / 4,000 characters',
          textAlign: TextAlign.right,
          style: TextStyle(color: overLimit ? colors.error : null),
        ),
        if (overLimit)
          Text(
            'Shorten the text to 4,000 characters or fewer.',
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
          child: const Text('Try narration again'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: controller.reset,
          child: const Text('Scan another page'),
        ),
      ],
    );
  }

  Widget _arFailure(
    String code,
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    late final IconData icon;
    late final String title;
    late final String message;
    var primaryLabel = 'Try AR again';
    VoidCallback onPrimary = controller.openCharacterReader;
    var secondaryLabel = 'Scan another page';
    VoidCallback onSecondary = controller.reset;

    switch (code) {
      case 'ar_unsupported':
        icon = Icons.tablet_mac_rounded;
        title = 'AR is not available';
        message = 'The character reader requires a physical iPad that supports '
            'AR world tracking.';
        primaryLabel = 'Scan another page';
        onPrimary = controller.reset;
        secondaryLabel = 'Close';
        onSecondary = () => Navigator.of(context).maybePop();
      case 'ar_unavailable':
        icon = Icons.tablet_mac_rounded;
        title = "We couldn't start AR";
        message = 'The character reader could not start this time. Your '
            'generated voice is still available.';
      case 'surface_not_found':
      case 'plane_not_found':
        icon = Icons.table_restaurant_outlined;
        title = "We couldn't find a flat surface";
        message =
            'Use a well-lit table or floor and move the iPad slowly while '
            'the character reader looks for a surface.';
      case 'model_missing':
        icon = Icons.smart_toy_outlined;
        title = 'The character is missing';
        message = 'The bundled character file is not available. Your generated '
            'voice is still saved for this flow.';
        primaryLabel = 'Scan another page';
        onPrimary = controller.reset;
        secondaryLabel = 'Close';
        onSecondary = () => Navigator.of(context).maybePop();
      case 'model_load_failed':
        icon = Icons.smart_toy_outlined;
        title = "The character couldn't load";
        message = 'The bundled character could not be opened. Your generated '
            'voice is still saved for this flow.';
        primaryLabel = 'Scan another page';
        onPrimary = controller.reset;
        secondaryLabel = 'Close';
        onSecondary = () => Navigator.of(context).maybePop();
      case 'audio_missing':
      case 'missing_audio':
        icon = Icons.audio_file_outlined;
        title = 'The generated voice is missing';
        message = 'The temporary narration file is no longer available. Create '
            'the voice again before opening the character reader.';
        primaryLabel = 'Create voice again';
        onPrimary = () => controller.confirmText(state.confirmedText);
      case 'audio_failed':
        icon = Icons.volume_off_outlined;
        title = "The character couldn't play the voice";
        message = 'Playback must be retried inside the character reader to '
            'preserve placement. From here, scan another page or close.';
        primaryLabel = 'Scan another page';
        onPrimary = controller.reset;
        secondaryLabel = 'Close';
        onSecondary = () => Navigator.of(context).maybePop();
      default:
        icon = Icons.view_in_ar_outlined;
        title = "We couldn't open the character reader";
        message = 'The character reader stopped before it could finish. Your '
            'generated voice is still available.';
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
