import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../library/story_cover.dart';
import '../player/player_providers.dart';

/// Story detail (§7.1.1 → §7.1.2 hand-off): cover hero, age/duration chips,
/// synopsis, the AR teaser, and the Read story CTA before the player opens.
class StoryDetailScreen extends ConsumerWidget {
  const StoryDetailScreen({super.key, required this.storyId});

  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final detail = ref.watch(storyDetailProvider(storyId));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: detail.when(
          loading: () => LoadingView(message: s.openingBook),
          error: (_, _) => ErrorView(
            message: s.couldNotOpenStory,
            onRetry: () => ref.invalidate(storyDetailProvider(storyId)),
          ),
          data: (d) {
            if (d == null) {
              return ErrorView(message: s.storyNotFound);
            }
            final story = d.story;

            String? themeLabel;
            if (story.themes.isNotEmpty) {
              themeLabel = switch (story.themes.first) {
                StoryTheme.animals => s.themeAnimals,
                StoryTheme.bedtime => s.themeBedtime,
                StoryTheme.friendship => s.themeFriendship,
                StoryTheme.emotions => s.themeEmotions,
                StoryTheme.languageLearning => s.themeLanguage,
              };
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 38),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 250,
                  child: BookCoverFrame(child: StoryCover(story: story)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      label: s.ageRange(story.ageRangeLabel),
                      selected: true,
                    ),
                    _MetaChip(
                        label: s.minutesFull(story.duration.inMinutes)),
                    if (themeLabel != null)
                      _MetaChip(
                        label: themeLabel,
                        gold: themeLabel == s.themeBedtime,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(story.title, style: Theme.of(context).textTheme.headlineMedium),
                if ((story.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      story.description!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: t.inkMuted),
                    ),
                  ),
                const SizedBox(height: 20),
                PaperCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.lavender.withValues(alpha: .16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.view_in_ar_rounded,
                            size: 22, color: t.lavender),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.arCalloutTitle,
                                style:
                                    Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 3),
                            Text(s.arCalloutBody,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                PressablePillButton(
                  label: s.readStory,
                  icon: Icons.menu_book_rounded,
                  onPressed: () =>
                      context.push(AppRoutes.storyRead(story.id)),
                ),
                const SizedBox(height: 12),
                PressablePillButton(
                  label: s.downloadForLater,
                  icon: Icons.download_rounded,
                  variant: PillVariant.secondary,
                  // Offline downloads ship in a later slice; rendered for
                  // design parity until then (spec §3).
                  onPressed: null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.paper,
            border: Border.all(color: t.line),
          ),
          child: Icon(icon, size: 20, color: t.ink),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.selected = false, this.gold = false});

  final String label;
  final bool selected;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    final Color bg;
    if (selected) {
      bg = t.lavenderContainer;
    } else if (gold) {
      bg = t.gold.withValues(alpha: .35);
    } else {
      bg = Colors.transparent;
    }
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: selected || gold ? null : Border.all(color: t.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.sansFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : t.inkMuted,
        ),
      ),
    );
  }
}
