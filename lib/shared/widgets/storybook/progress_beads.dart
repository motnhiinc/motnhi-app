import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Bead-style progress indicator (design system: replaces linear bars).
/// Either [currentIndex] (single active bead) or [activeCount] (fill-up style).
class ProgressBeads extends StatelessWidget {
  const ProgressBeads({
    super.key,
    required this.count,
    this.currentIndex,
    this.activeCount,
    this.size = 8,
    this.spacing = 6,
    this.alignment = WrapAlignment.start,
  });

  final int count;
  final int? currentIndex;
  final int? activeCount;
  final double size;
  final double spacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Wrap(
      alignment: alignment,
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isActive(i) ? t.coral : t.line,
            ),
          ),
      ],
    );
  }

  bool _isActive(int i) =>
      currentIndex != null ? i == currentIndex : i < (activeCount ?? 0);
}
