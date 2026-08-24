import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Warm-shadow paper card (22px radius) — the default surface of the system.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Material(
      color: color ?? t.paper,
      shadowColor: t.shadow,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
