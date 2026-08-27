import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../dashboard/dashboard_providers.dart';
import '../profile/profile_providers.dart';
import '../settings/settings_providers.dart';
import 'library_providers.dart';
import 'story_cover.dart';

/// The child home (§7.1.1): greeting, jump-back-in hero, theme-filtered story
/// grid, and the floating Stories / My books / Moon mode navigation. A small
/// "Parent area" chip leads through the gated parent surface.
class ChildHomeScreen extends ConsumerWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final library = ref.watch(libraryProvider);
    final profile = ref.watch(childProfileProvider).value;
    final selectedTheme = ref.watch(libraryThemeFilterProvider);
    final recents = ref.watch(dashboardSummaryProvider).value?.recentStories;

    final greeting = _greetingFor(s);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EyebrowLabel(greeting),
                          const SizedBox(height: 4),
                          Text(
                            profile?.nickname ?? s.appTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: 26),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ParentAreaChip(label: s.parentArea),
                  ],
                ),
                if (recents != null && recents.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _JumpBackInCard(story: recents.first),
                ],
                const SizedBox(height: 28),
                EyebrowLabel(s.forYou, color: Theme.of(context).colorScheme.onSurface),
                const SizedBox(height: 10),
                _ThemeFilterBar(selected: selectedTheme),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.scanAnyPage),
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: Text(s.scanTitle),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    EyebrowLabel(s.pickAStory,
                        color: Theme.of(context).colorScheme.onSurface),
                    GestureDetector(
                      onTap: () => ref
                          .read(libraryThemeFilterProvider.notifier)
                          .select(null),
                      child: Text(
                        s.seeAll,
                        style: TextStyle(
                          fontFamily: AppTheme.sansFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: context.stitch.coral,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                library.when(
                  loading: () => Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: LoadingView(message: s.findingStories),
                  ),
                  error: (_, _) => ErrorView(
                    message: s.libraryError,
                    onRetry: () => ref.invalidate(libraryProvider),
                  ),
                  data: (stories) {
                    if (stories.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Center(child: Text(s.libraryEmpty)),
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisExtent: 232,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                      ),
                      itemCount: stories.length,
                      itemBuilder: (_, i) => _StoryCard(story: stories[i]),
                    );
                  },
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingNavBar(items: [
                FloatingNavItem(
                  icon: Icons.auto_stories_rounded,
                  label: s.navStories,
                  active: true,
                  onTap: () {},
                ),
                FloatingNavItem(
                  icon: Icons.menu_book_rounded,
                  label: s.navMyBooks,
                  onTap: () => context.go(AppRoutes.myBooks),
                ),
                FloatingNavItem(
                  icon: Icons.dark_mode_rounded,
                  label: s.navMoonMode,
                  onTap: () => ref.read(bedtimeModeProvider.notifier).toggle(),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _greetingFor(AppLocalizations s) {
    final hour = DateTime.now().hour;
    if (hour < 12) return s.greetingMorning;
    if (hour < 18) return s.greetingAfternoon;
    return s.greetingEvening;
  }
}

class _ParentAreaChip extends StatelessWidget {
  const _ParentAreaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.parent),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.line),
            boxShadow: [
              BoxShadow(color: t.shadow, blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 16, color: t.coralDeep),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.sansFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JumpBackInCard extends StatelessWidget {
  const _JumpBackInCard({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PaperCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EyebrowLabel(s.jumpBackIn,
              color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 62,
                height: 82,
                child: BookCoverFrame(child: StoryCover(story: story)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ((story.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          story.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PressablePillButton(
            label: s.resumeReading,
            icon: Icons.play_arrow_rounded,
            height: 44,
            onPressed: () => context.go(AppRoutes.storyRead(story.id)),
          ),
        ],
      ),
    );
  }
}

class _ThemeFilterBar extends ConsumerWidget {
  const _ThemeFilterBar({required this.selected});

  final StoryTheme? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final notifier = ref.read(libraryThemeFilterProvider.notifier);

    String label(StoryTheme theme) => switch (theme) {
          StoryTheme.animals => s.themeAnimals,
          StoryTheme.bedtime => s.themeBedtime,
          StoryTheme.friendship => s.themeFriendship,
          StoryTheme.emotions => s.themeEmotions,
          StoryTheme.languageLearning => s.themeLanguage,
        };

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          _FilterChip(
            label: s.themeAll,
            selected: selected == null,
            onTap: () => notifier.select(null),
          ),
          for (final theme in StoryTheme.values)
            _FilterChip(
              label: label(theme),
              selected: selected == theme,
              onTap: () => notifier.select(theme),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.lavenderContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: t.line),
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
        ),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final locked = !story.isUnlocked;

    return GestureDetector(
      onTap: locked
          ? null
          : () => context.go(AppRoutes.storyDetail(story.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCoverFrame(child: StoryCover(story: story)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.paper.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${s.ageRange(story.ageRangeLabel)} · ${s.minutesShort(story.duration.inMinutes)}',
                      style: TextStyle(
                        fontFamily: AppTheme.sansFamily,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ),
                ),
                if (story.isAuthored)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.lavenderContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        s.madeByYou,
                        style: const TextStyle(
                          fontFamily: AppTheme.sansFamily,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C2452),
                        ),
                      ),
                    ),
                  ),
                if (story.isDownloaded)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: t.paper,
                      child: const Icon(Icons.download_done_rounded, size: 16),
                    ),
                  ),
                if (locked)
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.vertical(
                        top: const Radius.circular(42),
                        bottom: Radius.circular(AppTheme.cardRadius),
                      ),
                    ),
                    child:
                        const Icon(Icons.lock_rounded, color: Colors.white, size: 34),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            story.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
