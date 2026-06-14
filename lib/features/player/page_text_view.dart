import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import 'narration_player.dart';

/// Renders a page's narration as tappable text, highlighting the sentence the
/// narration engine is currently speaking (§7.1.2). Each segment is tappable to
/// jump playback to it.
class PageTextView extends StatelessWidget {
  const PageTextView({
    super.key,
    required this.segments,
    required this.player,
    required this.isActivePage,
    required this.onTapSegment,
  });

  final List<NarrationSegment> segments;
  final NarrationPlayer player;
  final bool isActivePage;
  final ValueChanged<int> onTapSegment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.headlineSmall!.copyWith(height: 1.4);

    return ValueListenableBuilder<int>(
      valueListenable: player.currentSegmentIndex,
      builder: (context, activeIndex, _) {
        return RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: baseStyle,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                TextSpan(
                  text: segments[i].text,
                  style: (isActivePage && i == activeIndex)
                      ? baseStyle.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          backgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.12),
                        )
                      : baseStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => onTapSegment(i),
                ),
                const TextSpan(text: ' '),
              ],
            ],
          ),
        );
      },
    );
  }
}
