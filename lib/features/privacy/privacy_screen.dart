import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/privacy_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../dashboard/dashboard_providers.dart';
import '../profile/profile_providers.dart';
import 'privacy_providers.dart';

/// Parent privacy & data controls (§14): stored-data counts, the optional
/// processing choices, reading-history deletion, and the two-step full
/// child-data deletion. Reached only through the parental gate
/// (`/parent/privacy`).
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> _setProgressTracking(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      // The notifier resolves only after the server committed the change, so
      // the retain/delete dialog below opens with server-confirmed state.
      await ref.read(privacyProvider.notifier).setProgressTracking(enabled);
      if (!mounted) return;
      if (!enabled) {
        final deleteHistory = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(s.privacyTrackingOffConfirmTitle),
            content: Text(s.privacyTrackingOffConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(s.privacyTrackingOffRetain),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(s.privacyTrackingOffDelete),
              ),
            ],
          ),
        );
        if (deleteHistory == true) {
          await ref.read(privacyProvider.notifier).deleteReadingHistory();
          ref.invalidate(dashboardStateProvider);
          _showMessage(s.privacyHistoryDeleted);
        }
        // Dismissal/retain: nothing else to do — history is kept.
      } else {
        ref.invalidate(dashboardStateProvider);
      }
    } catch (_) {
      _showMessage(s.privacySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCloudTts(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      await ref.read(privacyProvider.notifier).setCloudTts(enabled);
    } catch (_) {
      _showMessage(s.privacySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPageImageValidation(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      await ref.read(privacyProvider.notifier).setPageImageValidation(enabled);
    } catch (_) {
      _showMessage(s.privacySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReadingHistory() async {
    if (_busy) return;
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.privacyHistoryDeleteConfirmTitle),
        content: Text(s.privacyHistoryDeleteConfirmBody),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(privacyProvider.notifier).deleteReadingHistory();
      ref.invalidate(dashboardStateProvider);
      _showMessage(s.privacyHistoryDeleted);
    } catch (_) {
      _showMessage(s.privacySaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAllChildData() async {
    if (_busy) return;
    final s = AppLocalizations.of(context)!;
    // First confirmation.
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
    if (confirmed != true || !mounted) return;
    // Second confirmation: explicitly enumerates everything that will be
    // permanently deleted. Only this dialog's destructive button proceeds.
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.privacyFullDeleteFinalTitle),
        content: Text(s.privacyFullDeleteFinalBody),
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
            child: Text(s.privacyDeletePermanently),
          ),
        ],
      ),
    );
    if (finalConfirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(privacyProvider.notifier).deleteChildData();
      ref.invalidate(privacyProvider);
      ref.invalidate(childProfileProvider);
      ref.invalidate(dashboardStateProvider);
      // The access router takes over: profile is gone, so the parent is sent
      // to onboarding.
    } on PrivacyFailure {
      _showMessage(s.privacyDeleteFailed);
    } catch (_) {
      _showMessage(s.privacyDeleteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final privacy = ref.watch(privacyProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: privacy.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(
            message: s.privacyLoadError,
            onRetry: () => ref.invalidate(privacyProvider),
          ),
          data: (p) => ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.parent),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.paper,
                        border: Border.all(color: t.line),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: t.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.privacyScreenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Policy version / date + link to the full notice.
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.privacy_tip_outlined,
                          size: 20,
                          color: t.sage,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.privacyPolicyVersionLabel(p.currentPolicyVersion),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.privacyPolicyUpdatedLabel(_formatDate(p.updatedAt)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.privacyNotice),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(s.privacyNoticeCta),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Stored-data counts (transparency view, §14).
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EyebrowLabel(
                      s.privacyStoredTitle,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(height: 10),
                    _CountRow(
                      label: s.privacyCountProfiles(p.counts.childProfiles),
                    ),
                    _CountRow(
                      label: s.privacyCountAuthoredStories(
                        p.counts.authoredStories,
                      ),
                    ),
                    _CountRow(
                      label: s.privacyCountSessions(p.counts.storySessions),
                    ),
                    _CountRow(
                      label: s.privacyCountEvents(p.counts.interactionEvents),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Optional choices.
              PaperCard(
                child: _SwitchTile(
                  title: s.privacyTrackingTitle,
                  subtitle: s.privacyTrackingBody,
                  value: p.progressTrackingEnabled,
                  onChanged: _busy ? null : _setProgressTracking,
                ),
              ),
              const SizedBox(height: 12),
              PaperCard(
                child: _SwitchTile(
                  title: s.privacyCloudTitle,
                  subtitle: s.privacyCloudBody,
                  value: p.cloudTtsEnabled,
                  onChanged: _busy ? null : _setCloudTts,
                ),
              ),
              const SizedBox(height: 12),
              PaperCard(
                child: _SwitchTile(
                  title: s.privacyPageImageTitle,
                  subtitle: s.privacyPageImageBody,
                  value: p.pageImageValidationEnabled,
                  onChanged: _busy ? null : _setPageImageValidation,
                ),
              ),
              const SizedBox(height: 12),

              // Retained reading history: visible whenever sessions exist
              // (tracking off + retained, or tracking on with history).
              if (p.counts.storySessions > 0) ...[
                PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!p.progressTrackingEnabled) ...[
                        Text(
                          s.privacyRetainedHistoryNote,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _deleteReadingHistory,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        icon: const Icon(Icons.history_rounded),
                        label: Text(s.privacyRetainedHistoryAction),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 90-day inactivity statement.
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.privacyInactivityTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.privacyInactivityBody,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Destructive: full child-data deletion, two confirmations.
              OutlinedButton.icon(
                onPressed: _busy ? null : _deleteAllChildData,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.privacyDeleteDataButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 5),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
