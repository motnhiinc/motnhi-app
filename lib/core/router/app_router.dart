import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/parent_dashboard_screen.dart';
import '../../features/library/child_home_screen.dart';
import '../../features/library/my_books_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/parental_gate/parental_gate_providers.dart';
import '../../features/parental_gate/parental_gate_screen.dart';
import '../../features/player/story_player_screen.dart';
import '../../features/profile/profile_providers.dart';
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
  static const scanAnyPage = '/scan-any-page';
  static const createStory = '/create-story';

  /// Story detail precedes the reader; the reader lives one hop deeper.
  static String storyDetail(String id) => '/story/$id/detail';
  static String storyRead(String id) => '/story/$id/read';
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final onboarded = ref.read(isOnboardedProvider);
      final loc = state.matchedLocation;

      // Onboarding gate (§7.2.1): nothing else is reachable until consent +
      // profile exist.
      final goingToOnboarding = loc == AppRoutes.onboarding;
      if (!onboarded && !goingToOnboarding) return AppRoutes.onboarding;
      if (onboarded && goingToOnboarding) return AppRoutes.home;

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
      if (kDebugMode)
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
    ],
  );
});

/// Bridges Riverpod state changes into a [Listenable] for go_router so guards
/// re-evaluate when onboarding or gate state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(isOnboardedProvider, (_, _) => notifyListeners());
    ref.listen(parentalGateUnlockedProvider, (_, _) => notifyListeners());
  }
}
