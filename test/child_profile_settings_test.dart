import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/features/settings/child_profile_settings.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';

void main() {
  testWidgets('parent changes age and clears optional nickname',
      (tester) async {
    final saved = <(AgeBand, String?)>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChildProfileSettings(
          profile: const ChildProfile(
            id: 'child',
            ageBand: AgeBand.fiveToSix,
            nickname: 'Toan',
          ),
          onSave: (age, nickname) async => saved.add((age, nickname)),
        ),
      ),
    ));

    await tester.tap(find.text('Child profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7–8 yrs'));
    await tester.enterText(find.byType(TextField), '  ');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Save child profile'));
    await tester.tap(find.text('Save child profile'));
    await tester.pumpAndSettle();

    expect(saved, [(AgeBand.sevenToEight, null)]);
  });
}
