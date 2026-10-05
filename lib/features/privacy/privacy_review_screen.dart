import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/privacy_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../profile/profile_providers.dart';
import 'privacy_providers.dart';
import 'privacy_save_error.dart';

/// Policy review / re-review surface (§14.2). Shown when consent is missing or
/// stale. Presents the current required disclosure and the two optional
/// choices (off by default); "Review and continue" submits consent, after
/// which the access router sends the parent to onboarding for profile entry
/// (or home when the profile already exists).
class PrivacyReviewScreen extends ConsumerStatefulWidget {
  const PrivacyReviewScreen({super.key});

  @override
  ConsumerState<PrivacyReviewScreen> createState() =>
      _PrivacyReviewScreenState();
}

class _PrivacyReviewScreenState extends ConsumerState<PrivacyReviewScreen> {
  bool _progressTracking = false; // optional, off by default (§14.2)
  bool _cloudNarration = false; // optional, off by default (§14.2)
  bool _pageImageValidation = false;
  bool _submitting = false;
  bool _deleting = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_submitting || _deleting) return;
    setState(() => _submitting = true);
    final s = AppLocalizations.of(context)!;
    try {
      final privacy = ref.read(privacyProvider).value;
      final consentCurrent = privacy != null &&
          privacy.acceptedPolicyVersion != null &&
          privacy.acceptedPolicyVersion == privacy.currentPolicyVersion;
      if (!consentCurrent) {
        final policyVersion = privacy?.currentPolicyVersion;
        if (policyVersion == null) {
          // No server truth for the required policy version — do not guess.
          ref.invalidate(privacyProvider);
          showPrivacySaveError(context, s.privacySaveError,
              const PrivacyFailure('policy_unavailable'));
          return;
        }
        await ref.read(privacyProvider.notifier).updatePrivacy(
              policyVersion: policyVersion,
              coreStorageAccepted: true,
              progressTrackingEnabled: _progressTracking,
              cloudTtsEnabled: _cloudNarration,
              pageImageValidationEnabled: _pageImageValidation,
            );
      }
      // No explicit navigation: the access router sends the parent to
      // onboarding (no profile yet) or home (profile exists) once consent is
      // current.
    } on PrivacyFailure catch (e) {
      // Refresh policy state so the next retry uses fresh server truth.
      ref.invalidate(privacyProvider);
      if (mounted) showPrivacySaveError(context, s.privacySaveError, e);
    } catch (_) {
      _showError(s.setupError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteAllChildData() async {
    if (_submitting || _deleting) return;
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.privacyDeleteConfirmTitle),
        content: Text(s.privacyDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(s.deleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(privacyRepositoryProvider).deleteChildData();
      ref.invalidate(privacyProvider);
      ref.invalidate(childProfileProvider);
      // The access router takes over: profile is gone, so the parent is sent
      // to onboarding.
    } on PrivacyFailure {
      _showError(s.privacyDeleteFailed);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    return Scaffold(
      appBar: AppBar(title: Text(s.privacyReviewTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            Text(
              s.privacyReviewIntro,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: 20),

            // Required disclosure.
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.privacyStorageRequiredTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.privacyStorageRequiredBody,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Optional choices — off by default (§14.2).
            PaperCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _progressTracking,
                onChanged: (v) => setState(() => _progressTracking = v),
                title: Text(
                  s.privacyTrackingTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  s.privacyTrackingBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            PaperCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _pageImageValidation,
                onChanged: (v) => setState(() => _pageImageValidation = v),
                title: Text(
                  s.privacyPageImageTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  s.privacyPageImageBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            PaperCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cloudNarration,
                onChanged: (v) => setState(() => _cloudNarration = v),
                title: Text(
                  s.privacyCloudTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  s.privacyCloudBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.privacyReviewAcceptNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 20),
            _submitting
                ? const Center(child: CircularProgressIndicator())
                : PressablePillButton(
                    label: s.privacyReviewContinue,
                    onPressed: _submit,
                  ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: (_submitting || _deleting) ? null : _openFullNotice,
              child: Text(s.privacyNoticeCta),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed:
                  (_submitting || _deleting) ? null : _deleteAllChildData,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline),
              label: Text(
                _deleting ? s.privacyDeleting : s.privacyDeleteDataButton,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullNotice() {
    context.push(AppRoutes.privacyNotice);
  }
}
