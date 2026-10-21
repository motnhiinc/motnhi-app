import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:storybook_ar/core/router/app_router.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/library/child_home_screen.dart';
import 'package:storybook_ar/features/library/library_providers.dart';
import 'package:storybook_ar/features/profile/profile_providers.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';

class _Profile extends ChildProfileNotifier {
  @override
  Future<ChildProfile?> build() async => const ChildProfile(
    id: 'child',
    ageBand: AgeBand.fiveToSix,
    languageCode: 'en',
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const ChildHomeScreen()),
      GoRoute(
        path: AppRoutes.scanAnyPage,
        builder: (_, _) => const Scaffold(body: Text('Scan route')),
      ),
      GoRoute(
        path: AppRoutes.browseStories,
        builder: (_, _) => const Scaffold(body: Text('Full library route')),
      ),
      GoRoute(
        path: AppRoutes.myBooks,
        builder: (_, _) => const Scaffold(body: Text('My books route')),
      ),
      GoRoute(
        path: AppRoutes.parent,
        builder: (_, _) => const Scaffold(body: Text('Parent route')),
      ),
      GoRoute(
        path: '/story/:storyId/detail',
        builder: (_, state) =>
            Scaffold(body: Text('Story ${state.pathParameters['storyId']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        childProfileProvider.overrideWith(_Profile.new),
        homeStoryShelfProvider.overrideWith((ref) async {
          fail('The MVP home must not request the story catalog');
        }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.day(),
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home offers Scan without story picking or a library request', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(find.text('Scan my book'), findsOneWidget);
    expect(find.text('Little Fox'), findsNothing);
    expect(find.text('Moon Garden'), findsNothing);
    expect(find.text('Third Story'), findsNothing);
    expect(find.text('More stories'), findsNothing);
    expect(find.text('Or pick a story'), findsNothing);
    expect(find.text('My books'), findsNothing);

    await tester.tap(find.text('Scan my book'));
    await tester.pumpAndSettle();
    expect(find.text('Scan route'), findsOneWidget);
  });

  testWidgets('Home retains the parent area', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.text('Parent'));
    await tester.pumpAndSettle();
    expect(find.text('Parent route'), findsOneWidget);
  });

  test('retired story links redirect to home but scan remains available', () {
    for (final path in [
      AppRoutes.browseStories,
      AppRoutes.myBooks,
      AppRoutes.createStory,
      AppRoutes.storyDetail('fox'),
      AppRoutes.storyRead('fox'),
    ]) {
      expect(mvpRouteRedirect(path), AppRoutes.home);
    }
    expect(mvpRouteRedirect(AppRoutes.scanAnyPage), isNull);
    expect(mvpRouteRedirect(AppRoutes.parent), isNull);
  });

  testWidgets('Vietnamese Home keeps the scan action on a small screen', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      size: const Size(320, 568),
      locale: const Locale('vi'),
    );
    expect(find.text('Quét sách của bé'), findsOneWidget);
    await tester.ensureVisible(find.text('Quét sách của bé'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quét sách của bé'));
    await tester.pumpAndSettle();
    expect(find.text('Scan route'), findsOneWidget);
  });
}
