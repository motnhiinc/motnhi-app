import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'ar_reader_controller.dart';
import 'native_story_reader.dart';

/// Runs [controller] behind a modal that cannot be dismissed, and resolves to
/// the AR result (null when preparation failed).
///
/// The barrier is not decoration. Preparation takes seconds, and during it the
/// player underneath must stay unreachable: tapping play would start in-app
/// audio that then keeps sounding underneath the native AR screen, swiping
/// would send a stale initial page, and popping the route would dispose the
/// narration player and delete the very clips being copied.
///
/// The dialog drives the controller itself and pops with its own result, rather
/// than the caller racing a pop against a fast preparation.
Future<StoryReaderResult?> showArPreparingDialog(
  BuildContext context, {
  required ArReaderController controller,
}) {
  return showDialog<StoryReaderResult?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ArPreparingDialog(controller: controller),
  );
}

class _ArPreparingDialog extends StatefulWidget {
  const _ArPreparingDialog({required this.controller});

  final ArReaderController controller;

  @override
  State<_ArPreparingDialog> createState() => _ArPreparingDialogState();
}

class _ArPreparingDialogState extends State<_ArPreparingDialog> {
  @override
  void initState() {
    super.initState();
    // Started here rather than by the caller so the barrier is guaranteed to be
    // up before any preparation begins.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final result = await widget.controller.start();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<ArReaderState>(
          valueListenable: widget.controller,
          builder: (context, state, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Icon(
                  Icons.view_in_ar_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  _titleFor(s, state),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progressFor(state)),
                const SizedBox(height: 12),
                Text(
                  _messageFor(s, state),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _titleFor(AppLocalizations s, ArReaderState state) {
    switch (state.phase) {
      case ArReaderPhase.checkingSupport:
        return s.arPrepGettingReady;
      case ArReaderPhase.preparing:
        return s.arPrepGivingStory;
      case ArReaderPhase.opening:
      case ArReaderPhase.reading:
        return s.arPrepOpening;
      case ArReaderPhase.idle:
      case ArReaderPhase.failure:
        return s.arPrepOneMoment;
    }
  }

  static String _messageFor(AppLocalizations s, ArReaderState state) {
    if (state.phase == ArReaderPhase.opening ||
        state.phase == ArReaderPhase.reading) {
      return s.arPrepFindSurface;
    }
    if (state.total > 0) {
      return s.pageTitle(state.prepared, state.total);
    }
    return s.arPrepFirstTime;
  }

  /// Null while the total is unknown, which renders an indeterminate bar rather
  /// than one stuck at zero.
  static double? _progressFor(ArReaderState state) {
    if (state.phase != ArReaderPhase.preparing || state.total == 0) return null;
    return state.prepared / state.total;
  }
}
