import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';
import 'package:storybook_ar/features/scan_any_page/scan_child_states.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';

Future<void> _pumpState(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.day(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets('incomplete profile setup offers parent and home exits', (
    tester,
  ) async {
    var asked = false;
    var wentHome = false;
    await _pumpState(
      tester,
      ScanGrownUpHandoff(
        readyToRetry: false,
        onBack: () {},
        onPrimary: () => asked = true,
        onHome: () => wentHome = true,
      ),
    );
    expect(find.text('A grown-up can help.'), findsOneWidget);
    expect(find.text('Listen'), findsNothing);
    await tester.tap(find.text('Ask a grown-up'));
    expect(asked, isTrue);
    expect(find.text('Pick a story instead'), findsNothing);
    await tester.tap(find.text('Back to home'));
    expect(wentHome, isTrue);
  });

  testWidgets('blocked page offers rescan but never Listen', (tester) async {
    var rescanned = false;
    await _pumpState(
      tester,
      Scaffold(
        body: ScanChildState(
          icon: Icons.menu_book_rounded,
          title: "Let's try another page",
          body: "We can't read this one right now.",
          primaryLabel: 'Scan another page',
          onPrimary: () => rescanned = true,
        ),
      ),
    );
    expect(find.text('Listen'), findsNothing);
    await tester.tap(find.text('Scan another page'));
    expect(rescanned, isTrue);
  });

  testWidgets('preparing page has no playback action', (tester) async {
    await _pumpState(
      tester,
      const Scaffold(
        body: ScanChildState(
          icon: Icons.auto_stories_rounded,
          title: 'Making your page ready…',
          body: 'Just a moment.',
          loading: true,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Listen'), findsNothing);
  });

  testWidgets('Vietnamese handoff remains scrollable on a small phone', (
    tester,
  ) async {
    var asked = false;
    await _pumpState(
      tester,
      ScanGrownUpHandoff(
        readyToRetry: false,
        onBack: () {},
        onPrimary: () => asked = true,
        onHome: () {},
      ),
      size: const Size(320, 568),
      locale: const Locale('vi'),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Nhờ người lớn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhờ người lớn'));
    expect(asked, isTrue);
  });
}
