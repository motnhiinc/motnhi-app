import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Small tracked uppercase label that introduces a section ("eyebrow").
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: AppTheme.sansFamily,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        color: color ?? context.stitch.coralDeep,
      ),
    );
  }
}
