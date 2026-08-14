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

    return ListView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(24),
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
      return _FailureState(
        key: const ValueKey('arFailure'),
        title: "We couldn't open the character reader",
        message: 'This demo needs a supported physical iPad and a clear, '
            'well-lit flat surface.',
        primaryLabel: 'Try AR again',
        onPrimary: controller.openCharacterReader,
        secondaryLabel: 'Scan another page',
        onSecondary: controller.reset,
      );
    }
    if (code.startsWith('tts:') && code != 'tts:invalid_text') {
      return _ttsFailure(state, controller);
    }
    return _FailureState(
      key: const ValueKey('scanFailure'),
      title: code == 'tts:invalid_text'
          ? 'Check the text length'
          : "We couldn't read enough text",
      message: code == 'tts:invalid_text'
          ? 'Enter between 1 and 4,000 characters.'
          : 'Use one flat page with large, well-lit text. Avoid glare and keep '
              'all four corners visible.',
      primaryLabel: 'Scan again',
      onPrimary: () => _startScan(controller),
      secondaryLabel: 'Enter text manually',
      onSecondary: () {
        _textController.text = state.confirmedText;
        setState(() => _manualEntry = true);
      },
    );
  }

  Widget _ttsFailure(
    ScanAnyPageState state,
    ScanAnyPageController controller,
  ) {
    final count = _textController.text.runes.length;
    final overLimit = count > _maximumTextLength;
    final canRetry = _textController.text.trim().isNotEmpty && !overLimit;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('ttsFailure'),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 88,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 20),
        Text(
          "We couldn't create the voice",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Keep the Mac and iPad on the same Wi-Fi, then try again. Your text '
          'is still here and can be edited.',
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
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
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

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
          Icons.error_outline_rounded,
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
