import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import 'authored_stories_section.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../library/story_cover.dart';
import '../parental_gate/parental_gate_providers.dart';
import 'dashboard_providers.dart';

/// Private parent dashboard (§7.2.2): reading history, time, question accuracy,
/// and simple recommendations. Reached only through the parental gate.
class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () {
            ref.read(parentalGateUnlockedProvider.notifier).lock();
            context.go(AppRoutes.home);
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const LoadingView(),
        error: (_, _) =>
            const ErrorView(message: "We couldn't load the dashboard."),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatRow(summary: s),
            const SizedBox(height: 24),
            if (s.recentStories.isNotEmpty) ...[
              Text('Recently read',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _StoryStrip(stories: s.recentStories),
              const SizedBox(height: 24),
            ],
            Text('Suggested next',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _StoryStrip(stories: s.recommended),
            const AuthoredStoriesSection(),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final accuracy = (summary.questionAccuracy * 100).round();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.7,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.menu_book_rounded,
          label: 'Stories completed',
          value: '${summary.storiesCompleted}',
        ),
        _StatCard(
          icon: Icons.timer_outlined,
          label: 'Reading time',
          value: '${summary.totalReadingTime.inMinutes} min',
        ),
        _StatCard(
          icon: Icons.help_outline_rounded,
          label: 'Questions answered',
          value: '${summary.questionsAnswered}',
        ),
        _StatCard(
          icon: Icons.check_circle_outline_rounded,
          label: 'Question accuracy',
          value: summary.questionsAnswered == 0 ? '—' : '$accuracy%',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const Spacer(),
            Text(value, style: theme.textTheme.headlineSmall),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StoryStrip extends StatelessWidget {
  const _StoryStrip({required this.stories});

  final List<Story> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Nothing here yet.'),
      );
    }
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final story = stories[i];
          return SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: StoryCover(story: story),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  story.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
