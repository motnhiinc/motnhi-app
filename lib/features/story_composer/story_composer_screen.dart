import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../library/library_providers.dart';
import '../privacy/privacy_providers.dart';
import '../profile/profile_providers.dart';
import 'story_composer_controller.dart';

/// Capture several pages and save them as a new story.
///
/// The `/create-story` route is registered and this screen builds, but nothing
/// in the UI navigates to it yet — an entry point still has to be placed.
///
/// Not gated on kDebugMode and not behind the parental gate — the premise is a
/// child pointing the tablet at their own book. Deleting a story is gated
/// instead, on the parent dashboard.
class StoryComposerScreen extends ConsumerWidget {
  const StoryComposerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
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
      if (next.savedStoryId != null &&
          previous?.savedStoryId != next.savedStoryId) {
        ref.invalidate(libraryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.composerSavedToast)),
        );
        context.go(AppRoutes.home);
      }
      // First save attempt in a fresh flow: confirm cloud storage (§14.3).
      if (next.disclosurePending && previous?.disclosurePending != true) {
        _showCloudStorageDialog(context, s, notifier);
      }
      // Policy review required: refresh privacy state so the review screen
      // (router redirect) shows fresh server truth.
      if (next.failureCode == 'save:privacy_policy_review_required' &&
          previous?.failureCode != next.failureCode) {
        ref.invalidate(privacyProvider);
      }
    });

    final busy = state.phase == StoryComposerPhase.scanning ||
        state.phase == StoryComposerPhase.saving;

    return Scaffold(
      appBar: AppBar(title: Text(s.composerTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: s.composerNameLabel,
                  hintText: s.composerNameHint,
                ),
                maxLength: 120,
                onChanged: notifier.setTitle,
              ),
            ),
            if (state.failureCode != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _messageFor(s, state.failureCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: state.draft.pages.isEmpty
                  ? Center(child: Text(s.composerEmpty))
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
                          ? '…'
                          : s.composerAddPage),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PressablePillButton(
                      label: state.phase == StoryComposerPhase.saving
                          ? '…'
                          : s.composerSave,
                      icon: Icons.save_rounded,
                      height: 48,
                      onPressed:
                          (busy || !state.draft.isSaveable) ? null : notifier.save,
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

String _messageFor(AppLocalizations s, String failureCode) {
  if (failureCode == 'scan:no_text') {
    return s.composerScanFailed;
  }
  if (failureCode.startsWith('scan:')) {
    return s.composerScanFailed;
  }
  if (failureCode == 'save:quota_reached') {
    return s.composerTooManyPages;
  }
  if (failureCode == 'save:privacy_policy_review_required') {
    return s.composerPolicyReviewError;
  }
  if (failureCode == 'save:backend_unreachable' || failureCode == 'save:timeout') {
    return s.composerOfflineError;
  }
  return s.composerOfflineError;
}

/// Confirmation before the first save in each fresh composer flow (§14.3):
/// title and page text go to the app cloud; camera images never do. The
/// acknowledgement is per-flow widget state only — nothing is persisted.
Future<void> _showCloudStorageDialog(
  BuildContext context,
  AppLocalizations s,
  StoryComposerController notifier,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.composerDisclosureTitle),
      content: Text(s.composerDisclosureBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(s.composerDisclosureContinue),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    notifier.acknowledgeDisclosure();
    await notifier.save();
  } else {
    notifier.cancelDisclosure();
  }
}
