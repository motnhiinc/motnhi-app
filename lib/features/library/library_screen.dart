import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../profile/profile_providers.dart';
import '../settings/settings_providers.dart';
import 'library_providers.dart';
import 'story_cover.dart';

/// The child home: a calm grid of stories (§7.1.1, §26.1). No ads, no external
/// links, no infinite feed. A small "grown-ups" button leads to the gated
/// parent area.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final profile = ref.watch(childProfileProvider).value;
    final selectedTheme = ref.watch(libraryThemeFilterProvider);
    final bedtime = ref.watch(bedtimeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.nickname == null
            ? 'Story Time'
            : "${profile!.nickname}'s Stories"),
        actions: [
          IconButton(
            tooltip: 'Bedtime mode',
            icon: Icon(bedtime
                ? Icons.bedtime_rounded
                : Icons.bedtime_outlined),
            onPressed: () =>
                ref.read(bedtimeModeProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: 'Grown-ups',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: () => context.go(AppRoutes.parent),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ThemeFilterBar(selected: selectedTheme),
            Expanded(
              child: library.when(
                loading: () => const LoadingView(message: 'Finding stories…'),
                error: (e, _) => ErrorView(
                  message: "We couldn't load the stories.",
                  onRetry: () => ref.invalidate(libraryProvider),
                ),
                data: (stories) => stories.isEmpty
                    ? const Center(child: Text('No stories here yet.'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: 0.74,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: stories.length,
                        itemBuilder: (_, i) => _StoryCard(story: stories[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeFilterBar extends ConsumerWidget {
  const _ThemeFilterBar({required this.selected});

  final StoryTheme? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(libraryThemeFilterProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => notifier.select(null),
            ),
          ),
          for (final theme in StoryTheme.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(theme.label),
                selected: selected == theme,
                onSelected: (_) => notifier.select(theme),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = !story.isUnlocked;
    return GestureDetector(
      onTap: locked ? null : () => context.go(AppRoutes.story(story.id)),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoryCover(story: story),
                  if (locked)
                    Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 40),
                    ),
                  if (story.isDownloaded)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.download_done_rounded,
                          color: Colors.white),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ages ${story.ageRangeLabel} · ${story.duration.inMinutes} min',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
