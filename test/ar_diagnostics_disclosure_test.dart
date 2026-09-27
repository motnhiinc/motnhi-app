import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_diagnostics_disclosure.dart';
import 'package:storybook_ar/features/ar/ar_reader_diagnostic.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';

void main() {
  testWidgets('starts collapsed and reveals raw ARCore details on demand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ArDiagnosticsDisclosure(
            diagnostic: ArReaderDiagnostic(
              availability: 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
              decision: 'Unsupported',
              cause: 'UnavailableDeviceNotCompatibleException',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Technical details'), findsOneWidget);
    expect(find.textContaining('UNSUPPORTED_DEVICE_NOT_CAPABLE'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('UNSUPPORTED_DEVICE_NOT_CAPABLE'), findsOneWidget);
    expect(find.textContaining('Unsupported'), findsOneWidget);
    expect(
      find.textContaining('UnavailableDeviceNotCompatibleException'),
      findsOneWidget,
    );
  });
}
