import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../library/library_providers.dart';
import '../profile/profile_providers.dart';
import 'story_composer_controller.dart';

/// Capture several pages and save them as a new story. Reached from the
/// library app bar. Not gated on kDebugMode and not behind the parental gate —
/// the premise is a child pointing the tablet at their own book. Deleting a
/// story is gated instead, on the parent dashboard.
class StoryComposerScreen extends ConsumerWidget {
  const StoryComposerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Default to the child's language: list_published filters on language_code,
    // so saving in another language would make the story invisible afterwards
    // and a successful save would look like a failure.
    final language =
        ref.watch(childProfileProvider).value?.languageCode ?? 'en';
    final provider = storyComposerControllerProvider((
      scanService: ref.watch(scanServiceProvider),
      repository: ref.watch(authoredStoryRepositoryProvider),
      languageCode: language,
    ));
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen(provider, (previous, next) {
      if (next.savedStoryId == null ||
          previous?.savedStoryId == next.savedStoryId) {
        return;
      }
      ref.invalidate(libraryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Story saved.')),
      );
      context.go(AppRoutes.home);
    });

    final busy = state.phase == StoryComposerPhase.scanning ||
        state.phase == StoryComposerPhase.saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a story')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Story name',
                  border: OutlineInputBorder(),
                ),
                maxLength: 120,
                onChanged: notifier.setTitle,
              ),
            ),
            if (state.failureCode != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _messageFor(state.failureCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: state.draft.pages.isEmpty
                  ? const Center(child: Text('Scan a page to start your story.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.draft.pages.length,
                      itemBuilder: (_, i) {
                        final page = state.draft.pages[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Page ${i + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Remove page',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              notifier.removePage(page.localId),
                                    ),
                                  ],
                                ),
                                TextFormField(
                                  key: ValueKey(page.localId),
                                  initialValue: page.text,
                                  maxLines: null,
                                  maxLength: 4000,
                                  onChanged: (text) =>
                                      notifier.editPageText(page.localId, text),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : notifier.addPage,
                      icon: const Icon(Icons.document_scanner_rounded),
                      label: Text(state.phase == StoryComposerPhase.scanning
                          ? 'Scanning…'
                          : 'Add page'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          (busy || !state.draft.isSaveable) ? null : notifier.save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(state.phase == StoryComposerPhase.saving
                          ? 'Saving…'
                          : 'Save story'),
                    ),
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

String _messageFor(String failureCode) {
  if (failureCode == 'scan:no_text') {
    return "We couldn't read any words on that page. Try again with more light.";
  }
  if (failureCode.startsWith('scan:')) {
    return "The scan didn't work. Please try again.";
  }
  if (failureCode == 'save:quota_reached') {
    return 'You have reached the limit for saved stories. Delete one first.';
  }
  if (failureCode == 'save:backend_unreachable' ||
      failureCode == 'save:timeout') {
    return "We couldn't reach the story service. Check the connection and try again.";
  }
  return "We couldn't save the story. Please try again.";
}
