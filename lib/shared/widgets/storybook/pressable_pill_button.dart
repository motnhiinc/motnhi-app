import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pill-shaped button with the tactile "3D press" from the design system:
/// a solid [StitchTokens.coralPressed] underside that visually sinks when
/// tapped (primary) or a quiet outlined pill (secondary).
class PressablePillButton extends StatefulWidget {
  const PressablePillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = PillVariant.primary,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PillVariant variant;
  final bool expand;
  final double height;

  @override
  State<PressablePillButton> createState() => _PressablePillButtonState();
}

enum PillVariant { primary, secondary }

class _PressablePillButtonState extends State<PressablePillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    final enabled = widget.onPressed != null;
    final primary = widget.variant == PillVariant.primary;
    final sink = primary && _pressed && enabled;

    final decoration = BoxDecoration(
      color: primary ? t.coral : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      border: primary
          ? null
          : Border.all(color: enabled ? t.line : t.line.withValues(alpha: .5)),
      boxShadow: primary && enabled && !_pressed
          ? [
              BoxShadow(
                color: t.coralPressed,
                offset: const Offset(0, 4),
                blurRadius: 0,
              ),
            ]
          : const [],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            height: widget.height,
            width: widget.expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            transform: Matrix4.translationValues(0, sink ? 3 : 0, 0),
            decoration: decoration,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 19,
                    color: primary ? Colors.white : t.ink,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: primary ? Colors.white : t.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
