import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/parent_dashboard_screen.dart';
import '../../features/library/child_home_screen.dart';
import '../../features/library/my_books_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/parental_gate/parental_gate_providers.dart';
import '../../features/parental_gate/parental_gate_screen.dart';
import '../../features/player/story_player_screen.dart';
import '../../features/privacy/privacy_notice_screen.dart';
import '../../features/privacy/privacy_providers.dart';
import '../../features/privacy/privacy_review_screen.dart';
import '../../features/privacy/privacy_screen.dart';
import '../../features/scan_any_page/scan_any_page_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/story_composer/story_composer_screen.dart';
import '../../features/story_detail/story_detail_screen.dart';

/// Route paths. `/gate` is deliberately NOT under `/parent` so guarding
/// `/parent*` never traps the gate itself in a redirect loop.
abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const myBooks = '/my-books';
  static const gate = '/gate';
  static const parent = '/parent';
  static const settings = '/parent/settings';
  static const parentPrivacy = '/parent/privacy';
  static const scanAnyPage = '/scan-any-page';
  static const createStory = '/create-story';
  static const privacyReview = '/privacy-review';
  static const privacyNotice = '/privacy-notice';

  /// Story detail precedes the reader; the reader lives one hop deeper.
  static String storyDetail(String id) => '/story/$id/detail';
  static String storyRead(String id) => '/story/$id/read';
}

/// Pure access-redirect matrix (§14.2, fail-closed). The `/parent*` gate runs
/// separately in [goRouterProvider] and stays as-is.
String? appAccessRedirect(AppAccessState access, String loc) {
  switch (access.status) {
    case AppAccessStatus.loading:
    case AppAccessStatus.unavailable:
      return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
    case AppAccessStatus.setupRequired:
      return loc == AppRoutes.onboarding || loc == AppRoutes.privacyNotice
          ? null
          : AppRoutes.onboarding;
    case AppAccessStatus.policyReviewRequired:
      return loc == AppRoutes.privacyReview || loc == AppRoutes.privacyNotice
          ? null
          : AppRoutes.privacyReview;
    case AppAccessStatus.ready:
      if (loc == AppRoutes.onboarding || loc == AppRoutes.privacyReview) {
        return AppRoutes.home;
      }
  }
  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final access = ref.read(appAccessProvider);
      final loc = state.matchedLocation;

      // Access gate (§14.2, fail-closed): derived from server truth only.
      final accessRedirect = appAccessRedirect(access, loc);
      if (accessRedirect != null) return accessRedirect;

      // Parental gate (§7.2.3): guard parent-only surfaces.
      if (loc.startsWith(AppRoutes.parent)) {
        final unlocked = ref.read(parentalGateUnlockedProvider);
        if (!unlocked) {
          return '${AppRoutes.gate}?redirect=${Uri.encodeComponent(loc)}';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const ChildHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.myBooks,
        builder: (_, _) => const MyBooksScreen(),
      ),
      GoRoute(
        path: AppRoutes.scanAnyPage,
        builder: (_, _) => const ScanAnyPageScreen(),
      ),
      // Not kDebugMode-gated: capture-to-story ships in release builds.
      GoRoute(
        path: AppRoutes.createStory,
        builder: (_, _) => const StoryComposerScreen(),
      ),
      GoRoute(
        path: '/story/:storyId/detail',
        builder: (_, state) =>
            StoryDetailScreen(storyId: state.pathParameters['storyId']!),
      ),
      GoRoute(
        path: '/story/:storyId/read',
        builder: (_, state) =>
            StoryPlayerScreen(storyId: state.pathParameters['storyId']!),
      ),
      GoRoute(
        path: AppRoutes.gate,
        builder: (_, state) => ParentalGateScreen(
          redirectTo:
              state.uri.queryParameters['redirect'] ?? AppRoutes.parent,
        ),
      ),
      GoRoute(
        path: AppRoutes.parent,
        builder: (_, _) => const ParentDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const ReadingSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.parentPrivacy,
        builder: (_, _) => const PrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacyReview,
        builder: (_, _) => const PrivacyReviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacyNotice,
        builder: (_, _) => const PrivacyNoticeScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod state changes into a [Listenable] for go_router so guards
/// re-evaluate when access or gate state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(appAccessProvider, (_, _) => notifyListeners());
    ref.listen(parentalGateUnlockedProvider, (_, _) => notifyListeners());
  }
}
