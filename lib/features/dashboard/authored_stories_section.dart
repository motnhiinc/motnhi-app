import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/repositories/authored_story_repository.dart';
import '../../l10n/app_localizations.dart';
import '../library/library_providers.dart';

/// Grown-ups-only management of stories captured in the app.
///
/// Delete lives here, behind the parental gate, rather than in the child
/// library: it is destructive and a child must not be able to reach it.
class AuthoredStoriesSection extends ConsumerWidget {
  const AuthoredStoriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final library = ref.watch(libraryProvider);
    return library.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (stories) {
        final authored = stories.where((s) => s.isAuthored).toList();
        if (authored.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(s.storiesYouMade,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final story in authored)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(story.title),
                subtitle: Text(s.authoredStorySubtitle(story.ageRangeLabel)),
                trailing: IconButton(
                  tooltip: s.deleteStoryTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      _confirmDelete(context, ref, story.id, story.title),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String storyId,
    String title,
  ) async {
    final s = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteStoryTitle(title)),
        content: Text(s.deleteStoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.deleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authoredStoryRepositoryProvider).deleteStory(storyId);
      ref.invalidate(libraryProvider);
    } on AuthoredStoryFailure {
      messenger.showSnackBar(
        SnackBar(content: Text(s.deleteStoryFailed)),
      );
    }
  }
}
