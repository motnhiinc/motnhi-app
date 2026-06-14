import 'package:flutter/material.dart';

import '../../data/models/models.dart';

/// Renders a story's cover. Uses the bundled cover image when present; until
/// real art exists it falls back to a calm themed gradient with a glyph, so the
/// library always looks intentional rather than broken.
class StoryCover extends StatelessWidget {
  const StoryCover({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final asset = story.coverAssetId;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final colors = _gradientFor(story.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          _glyphFor(story.themes),
          style: const TextStyle(fontSize: 64),
        ),
      ),
    );
  }

  static List<Color> _gradientFor(String id) {
    final h = id.codeUnits.fold<int>(0, (a, c) => a + c);
    final palettes = <List<Color>>[
      [const Color(0xFFFFC988), const Color(0xFFEF7E54)],
      [const Color(0xFFB5E8C9), const Color(0xFF6FB8A0)],
      [const Color(0xFFCDBDF2), const Color(0xFF8B6FD6)],
      [const Color(0xFFFFB3C1), const Color(0xFFE26D8A)],
      [const Color(0xFFA7D8F0), const Color(0xFF5C9FD6)],
    ];
    return palettes[h % palettes.length];
  }

  static String _glyphFor(List<StoryTheme> themes) {
    if (themes.isEmpty) return '📖';
    return switch (themes.first) {
      StoryTheme.animals => '🐰',
      StoryTheme.bedtime => '🌙',
      StoryTheme.friendship => '🤝',
      StoryTheme.emotions => '💛',
      StoryTheme.languageLearning => '🔤',
    };
  }
}
