import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/privacy/privacy_providers.dart';
import 'features/settings/locale_providers.dart';
import 'features/settings/settings_providers.dart';
import 'l10n/app_localizations.dart';

/// App root. Bedtime mode (§7.1.6) swaps the whole app to the calm dark theme
/// via [ThemeMode]; UI language follows the system unless overridden in
/// Settings (EN/VI). Also observes app lifecycle to report daily foreground
/// activity (Task 22).
class StorybookApp extends ConsumerStatefulWidget {
  const StorybookApp({super.key});

  @override
  ConsumerState<StorybookApp> createState() => _StorybookAppState();
}

class _StorybookAppState extends ConsumerState<StorybookApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground activity is reported on `resumed` only — never on inactive,
    // paused, hidden, or detached (Task 22).
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(privacyActivityNotifierProvider).onForeground());
    }
  }

  @override
  Widget build(BuildContext context) {
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
