import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/core/router/app_router.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/privacy_repository.dart';
import 'package:storybook_ar/data/repositories/profile_repository.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/onboarding/onboarding_screen.dart';
import 'package:storybook_ar/features/privacy/privacy_providers.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';
import 'package:storybook_ar/shared/widgets/storybook/pressable_pill_button.dart';

class _PrivacyRepo implements PrivacyRepository {
  _PrivacyRepo(this.events);

  final List<String> events;
  int updates = 0;
  bool? tracking;
  bool? cloud;
  bool? pageCheck;

  PrivacyState get initial => PrivacyState(
        currentPolicyVersion: 'v1',
        reviewRequired: true,
        lastActiveAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );

  @override
  Future<PrivacyState> fetchPrivacy() async => initial;

  @override
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
    required bool pageImageValidationEnabled,
  }) async {
    events.add('privacy');
    updates++;
    expect(policyVersion, 'v1');
    expect(coreStorageAccepted, isTrue);
    tracking = progressTrackingEnabled;
    cloud = cloudTtsEnabled;
    pageCheck = pageImageValidationEnabled;
    return initial.copyWith(
      acceptedPolicyVersion: policyVersion,
      reviewRequired: false,
    );
  }

  @override
  Future<void> recordActivity() async {}
  @override
  Future<void> deleteReadingHistory() async {}
  @override
  Future<void> deleteChildData() async {}
}

class _ProfileRepo implements ProfileRepository {
  _ProfileRepo(this.events, {this.failFirst = false});

  final List<String> events;
  final bool failFirst;
  final saved = <ChildProfile>[];

  @override
  Future<ChildProfile?> getProfile() async => null;

  @override
  Future<void> saveProfile(ChildProfile profile) async {
    events.add('profile');
    saved.add(profile);
    if (failFirst && saved.length == 1) {
      throw const ProfileFailure('network');
    }
  }
}

Future<void> _pumpSetup(
  WidgetTester tester,
  _PrivacyRepo privacy,
  _ProfileRepo profile,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = await KeyValueStore.create();
  final container = ProviderContainer(overrides: [
    keyValueStoreProvider.overrideWithValue(store),
    privacyRepositoryProvider.overrideWithValue(privacy),
    profileRepositoryProvider.overrideWithValue(profile),
  ]);
  addTearDown(container.dispose);
  await container.read(privacyProvider.future);

  final router = GoRouter(initialLocation: AppRoutes.onboarding, routes: [
    GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingScreen()),
    GoRoute(
        path: AppRoutes.privacyNotice,
        builder: (_, _) => const Scaffold(body: Text('Full notice opened'))),
    GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('Home opened'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.day(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quick start has no fields, requires consent, and opens notice',
      (tester) async {
    final events = <String>[];
    final privacy = _PrivacyRepo(events);
    await _pumpSetup(tester, privacy, _ProfileRepo(events));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Starting at ages 5–6'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(
        tester
            .widget<PressablePillButton>(find.byType(PressablePillButton))
            .onPressed,
        isNull);
    expect(events, isEmpty);

    await tester.tap(find.text('Read full privacy notice'));
    await tester.pumpAndSettle();
    expect(find.text('Full notice opened'), findsOneWidget);
    expect(events, isEmpty);
  });

  testWidgets(
      'consent precedes default profile and profile retry skips consent',
      (tester) async {
    final events = <String>[];
    final privacy = _PrivacyRepo(events);
    final profile = _ProfileRepo(events, failFirst: true);
    await _pumpSetup(tester, privacy, profile);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();
    expect(events, ['privacy', 'profile']);
    expect(privacy.tracking, isFalse);
    expect(privacy.cloud, isFalse);
    expect(privacy.pageCheck, isFalse);
    expect(profile.saved.single.ageBand, AgeBand.fiveToSix);
    expect(profile.saved.single.nickname, isNull);
    expect(profile.saved.single.languageCode, 'en');
    expect(profile.saved.single.arEnabled, isTrue);
    expect(profile.saved.single.microphoneEnabled, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();
    expect(events, ['privacy', 'profile', 'profile']);
    expect(privacy.updates, 1);
    expect(profile.saved[1].id, profile.saved[0].id);
    expect(find.text('Home opened'), findsOneWidget);
  });
}
