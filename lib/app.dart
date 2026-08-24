import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/locale_providers.dart';
import 'features/settings/settings_providers.dart';
import 'l10n/app_localizations.dart';

/// App root. Bedtime mode (§7.1.6) swaps the whole app to the calm dark theme
/// via [ThemeMode]; UI language follows the system unless overridden in
/// Settings (EN/VI).
class StorybookApp extends ConsumerWidget {
  const StorybookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final bedtime = ref.watch(bedtimeModeProvider);
    final localeOverride = ref.watch(localeOverrideProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.day(),
      darkTheme: AppTheme.bedtime(),
      themeMode: bedtime ? ThemeMode.dark : ThemeMode.light,
      locale: localeOverride,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('vi')],
      routerConfig: router,
    );
  }
}
