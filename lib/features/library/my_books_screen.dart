import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../dashboard/dashboard_providers.dart';
import '../settings/settings_providers.dart';
import 'library_providers.dart';
import 'story_cover.dart';

enum _MyBooksFilter { downloaded, madeByYou, reading }

/// The child's own shelf: downloaded stories, capture-to-story creations, and
/// what they are currently reading — plus a gentle promo for more books.
class MyBooksScreen extends ConsumerStatefulWidget {
  const MyBooksScreen({super.key});

  @override
  ConsumerState<MyBooksScreen> createState() => _MyBooksScreenState();
}

class _MyBooksScreenState extends ConsumerState<MyBooksScreen> {
  _MyBooksFilter _filter = _MyBooksFilter.downloaded;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final library = ref.watch(libraryProvider);
    final summary = ref.watch(dashboardSummaryProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.myBooksTitle,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 26),
                      ),
                    ),
                    const Icon(Icons.search_rounded, size: 26),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Chip(
                      label: s.filterDownloaded,
                      selected: _filter == _MyBooksFilter.downloaded,
                      onTap: () =>
                          setState(() => _filter = _MyBooksFilter.downloaded),
                    ),
                    _Chip(
                      label: s.filterMadeByYou,
                      selected: _filter == _MyBooksFilter.madeByYou,
                      onTap: () => setState(
                          () => _filter = _MyBooksFilter.madeByYou),
                    ),
                    _Chip(
                      label: s.filterReading,
                      selected: _filter == _MyBooksFilter.reading,
                      onTap: () =>
                          setState(() => _filter = _MyBooksFilter.reading),
                    ),
                  ],
                ),
                if (summary != null && summary.recentStories.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      EyebrowLabel(s.sectionRecent,
                          color:
                              Theme.of(context).colorScheme.onSurface),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 178,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: summary.recentStories.length.clamp(0, 6),
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, i) {
                        final story = summary.recentStories[i];
                        return SizedBox(
                          width: 118,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 132,
                                child: BookCoverFrame(
                                  child: StoryCover(story: story),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                story.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontSize: 13),
                              ),
                              Text(
                                _categoryLabel(s, story),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.stitch.gold.withValues(alpha: .35),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '✦',
                          style: TextStyle(
                            fontSize: 18,
                            color: context.stitch.coralDeep,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(s.promoTitle,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(s.promoBody,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 14),
                      PressablePillButton(
                        label: s.exploreNow,
                        height: 44,
                        onPressed: () => ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(s.comingSoonToast))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                library.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, _) => Center(child: Text(s.libraryError)),
                  data: (stories) {
                    final shown = switch (_filter) {
                      _MyBooksFilter.downloaded =>
                        stories.where((st) => st.isDownloaded),
                      _MyBooksFilter.madeByYou =>
                        stories.where((st) => st.isAuthored),
                      _MyBooksFilter.reading => stories.where(
                        (st) => summary?.recentStories
                                .any((r) => r.id == st.id) ??
                            false,
                      ),
                    }.toList();
                    if (shown.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(child: Text(s.nothingYet)),
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisExtent: 210,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _ShelfCard(story: shown[i]),
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
                  onTap: () => context.go(AppRoutes.home),
                ),
                FloatingNavItem(
                  icon: Icons.menu_book_rounded,
                  label: s.navMyBooks,
                  active: true,
                  onTap: () {},
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

  String _categoryLabel(AppLocalizations s, Story story) {
    final theme = story.themes.isEmpty ? null : story.themes.first;
    return switch (theme) {
          StoryTheme.animals => s.themeAnimals,
          StoryTheme.bedtime => s.themeBedtime,
          StoryTheme.friendship => s.themeFriendship,
          StoryTheme.emotions => s.themeEmotions,
          StoryTheme.languageLearning => s.themeLanguage,
          null => '',
        } ;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: story.isUnlocked
          ? () => context.go(AppRoutes.storyDetail(story.id))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: BookCoverFrame(child: StoryCover(story: story))),
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
