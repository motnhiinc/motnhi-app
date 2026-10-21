import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../profile/profile_providers.dart';
import 'scan_book_illustration.dart';

/// Scan-only MVP home: no catalog requests or story-picking navigation.
class ChildHomeScreen extends ConsumerWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final profile = ref.watch(childProfileProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              EyebrowLabel(_greetingFor(s), color: t.sage),
                              const SizedBox(height: 2),
                              Text(
                                profile?.nickname == null
                                    ? s.childHomeGreeting
                                    : s.childHomeGreetingNamed(
                                        profile!.nickname!,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTheme.sansFamily,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: t.ink,
                                  letterSpacing: -1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          child: OutlinedButton.icon(
                            onPressed: () => context.go(AppRoutes.parent),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(44, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: t.sage,
                            ),
                            label: Text(
                              s.childHomeParent,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      decoration: BoxDecoration(
                        color: t.paper,
                        border: Border.all(color: t.line),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 190,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: t.sageContainer.withValues(alpha: .28),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ScanBookIllustration(
                              color: t.sage,
                              paper: t.paper,
                              coral: t.coral,
                              gold: t.gold,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            s.childHomeHeroTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTheme.sansFamily,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.8,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.childHomeHeroBody,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),
                          PressablePillButton(
                            label: s.scanMyBook,
                            icon: Icons.document_scanner_rounded,
                            height: 64,
                            onPressed: () =>
                                context.push(AppRoutes.scanAnyPage),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
