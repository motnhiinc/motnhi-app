import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Large, unmistakable play/pause control (§7.1.2 "large play button", §26.1).
class BigPlayButton extends StatelessWidget {
  const BigPlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.size = AppTheme.bigButtonSize,
  });

  final bool isPlaying;
  /// Null disables the button — used while a page's narration clip is
  /// still being fetched.
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: isPlaying ? 'Pause' : 'Play',
      child: Material(
        color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: size * 0.55,
              color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
