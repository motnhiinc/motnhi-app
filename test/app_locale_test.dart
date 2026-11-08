import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:storybook_ar/app.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/core/router/app_router.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/settings/locale_providers.dart';
import 'package:storybook_ar/features/settings/settings_providers.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';

void main() {
  test('App locale does not read a previously saved language override', () {
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWith((ref) {
        fail('App language must not depend on saved preferences');
      }),
    ]);
    addTearDown(container.dispose);

    expect(container.read(appLocaleProvider), const Locale('vi'));
  });

  for (final language in ['en', 'vi', 'fr']) {
    testWidgets('App stays Vietnamese on a $language device', (tester) async {
      tester.platformDispatcher.localeTestValue = Locale(language);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Text(Localizations.localeOf(context).languageCode),
          ),
        ),
      ]);
      addTearDown(router.dispose);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          goRouterProvider.overrideWithValue(router),
          settingsProvider.overrideWith(_Settings.new),
        ],
        child: const StorybookApp(),
      ));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('vi'));
      expect(app.supportedLocales, [const Locale('vi')]);
      expect(find.text('vi'), findsOneWidget);
      final context = tester.element(find.text('vi'));
      expect(AppLocalizations.of(context)!.localeName, 'vi');
    });
  }
}

class _Settings extends SettingsNotifier {
  @override
  Future<ReadingSettings> build() async => const ReadingSettings();
}
