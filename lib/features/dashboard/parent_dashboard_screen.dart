import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../parental_gate/parental_gate_providers.dart';
import 'dashboard_providers.dart';

/// Private parent dashboard (§7.2.2): a gentle weekly summary, the most
/// retained reading history and a link into Settings. Reached only
/// through the parental gate.
class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final state = ref.watch(dashboardStateProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: state.when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorView(message: s.libraryError),
          data: (d) => _Body(state: d),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final summary = state.summary;
    // Retained history stays readable with tracking off; the no-history
    // states (fresh start with tracking on, or tracking off with nothing ever
    // saved) show the same gentle empty card instead of zero stats (§14).
    final showStats =
        state.status == DashboardTrackingStatus.trackingOnWithHistory ||
        state.status == DashboardTrackingStatus.trackingOffRetainedHistory;
    // The two no-history states get their own copy: tracking off (nothing is
    // being saved) vs tracking on but nothing read yet.
    final emptyMessage =
        state.status == DashboardTrackingStatus.trackingOffNoHistory
        ? s.dashboardTrackingOffEmpty
        : s.nothingYet;
    final retainedHistory =
        state.status == DashboardTrackingStatus.trackingOffRetainedHistory;
    final accuracy = (summary.questionAccuracy * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                ref.read(parentalGateUnlockedProvider.notifier).lock();
                context.go(AppRoutes.home);
              },
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.paper,
                  border: Border.all(color: t.line),
                ),
                child: Icon(Icons.arrow_back_rounded, size: 20, color: t.ink),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.parentDashboard,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (!showStats) ...[
          const SizedBox(height: 18),
          PaperCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_rounded, size: 20, color: t.lavender),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 18),
          PaperCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${summary.storiesCompleted}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: t.coralDeep),
                      ),
                      Text(
                        s.statStoriesCompleted,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.minutesShort(summary.totalReadingTime.inMinutes),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: t.coralDeep, fontSize: 22),
                      ),
                      Text(
                        s.statReadingTime,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Retained history with tracking off: say so, without claiming the
          // child is being tracked now.
          if (retainedHistory) ...[
            Text(
              s.dashboardRetainedNote,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: 8),
          ],
          // Stories completed is not repeated here: it is already the headline
          // figure in the summary card above.
          Row(
            children: [
              _StatTile(
                value: '${summary.questionsAnswered}',
                label: s.statQuestionsAnswered,
              ),
              const SizedBox(width: 12),
              _StatTile(
                value: summary.questionsAnswered == 0 ? '—' : '$accuracy%',
                label: s.statAccuracy,
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _LinkRow(
          icon: Icons.shield_rounded,
          iconColor: t.coralDeep,
          label: s.settingsRow,
          onTap: () => context.go(AppRoutes.settings),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return Expanded(
      child: PaperCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: t.coralDeep),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PaperCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: context.stitch.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
