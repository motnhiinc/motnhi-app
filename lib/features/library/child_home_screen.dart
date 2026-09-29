import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../profile/profile_providers.dart';
import 'library_providers.dart';
import 'scan_book_illustration.dart';
import 'story_cover.dart';

/// Scan-first child home. The complete filtered library lives at /stories.
class ChildHomeScreen extends ConsumerWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final profile = ref.watch(childProfileProvider).value;
    final library = ref.watch(homeStoryShelfProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 112),
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
                                        profile!.nickname!),
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(Icons.shield_outlined,
                                size: 16, color: t.sage),
                            label: Text(s.childHomeParent,
                                style: const TextStyle(fontSize: 12)),
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
                                gold: t.gold),
                          ),
                          const SizedBox(height: 14),
                          Text(s.childHomeHeroTitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.sansFamily,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8,
                                color: t.ink,
                              )),
                          const SizedBox(height: 2),
                          Text(s.childHomeHeroBody,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium),
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
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.childHomePickStory,
                              style: TextStyle(
                                fontFamily: AppTheme.sansFamily,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: t.ink,
                              )),
                        ),
                        TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.browseStories),
                          child: Text(s.childHomeMoreStories),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    library.when(
                      loading: () => const SizedBox(
                          height: 118,
                          child: Center(child: CircularProgressIndicator())),
                      error: (_, _) => _ShelfMessage(
                        message: s.libraryError,
                        action: s.retry,
                        onAction: () => ref.invalidate(homeStoryShelfProvider),
                      ),
                      data: (stories) {
                        final shown = stories
                            .where((story) => story.isUnlocked)
                            .take(2)
                            .toList();
                        if (shown.isEmpty) {
                          return _ShelfMessage(message: s.libraryEmpty);
                        }
                        return Row(
                          children: [
                            for (var i = 0; i < shown.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(child: _StoryPreview(story: shown[i])),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingNavBar(items: [
                FloatingNavItem(
                  icon: Icons.home_rounded,
                  label: s.childHomeNavHome,
                  active: true,
                  onTap: () {},
                ),
                FloatingNavItem(
                  icon: Icons.menu_book_rounded,
                  label: s.navMyBooks,
                  onTap: () => context.go(AppRoutes.myBooks),
                ),
              ]),
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

class _StoryPreview extends StatelessWidget {
  const _StoryPreview({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: story.title,
      child: InkWell(
        onTap: () => context.go(AppRoutes.storyDetail(story.id)),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 118,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: context.stitch.line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              StoryCover(story: story),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: context.stitch.paper.withValues(alpha: .94),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(
                    story.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  const _ShelfMessage({required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 118,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}
