import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_providers.dart';

/// App root. Bedtime mode (§7.1.6) swaps the whole app to the calm dark theme
/// via [ThemeMode].
class StorybookApp extends ConsumerWidget {
  const StorybookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final bedtime = ref.watch(bedtimeModeProvider);

    return MaterialApp.router(
      title: 'Storybook AR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.day(),
      darkTheme: AppTheme.bedtime(),
      themeMode: bedtime ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}
