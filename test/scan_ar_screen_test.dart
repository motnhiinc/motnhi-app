import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/sources/key_value_store.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/profile/profile_providers.dart';
import 'package:storybook_ar/features/scan_any_page/scan_any_page_screen.dart';
import 'package:storybook_ar/features/scan_any_page/scan_page_coordinator.dart';
import 'package:storybook_ar/l10n/app_localizations.dart';
import 'helpers/scan_ar_fakes.dart';

class _Profile extends ChildProfileNotifier {
  _Profile(this.enabled);
  final bool enabled;
  @override
  Future<ChildProfile?> build() async => ChildProfile(
    id: 'profile',
    ageBand: AgeBand.threeToFour,
    arEnabled: enabled,
  );
}

class _AutomaticReader extends ArTestReader implements PreparingStoryReader {
  final preparingOpened = Completer<void>();
  final narrationAttached = Completer<void>();
  final terminal = Completer<StoryReaderResult>();
  @override
  Future<StoryReaderResult> openPreparing({
    required String sessionId,
    required ArCharacter character,
  }) {
    opens++;
    this.character = character;
    preparingOpened.complete();
    return terminal.future;
  }

  @override
  Future<void> attachNarration({
    required String sessionId,
    required List<ArNarrationPage> pages,
  }) async {
    this.pages = pages;
    narrationAttached.complete();
  }

  @override
  Future<void> closePreparing(String sessionId) async {
    if (!terminal.isCompleted) {
      terminal.complete(
        const StoryReaderResult(
          terminalCode: 'cancelled',
          lastPageId: null,
          pagesRead: [],
        ),
      );
    }
  }
}

void main() {
  late Directory directory;
  late ScanPageCoordinator session;
  late ArTestReader reader;
  late ArTestClient client;
  late KeyValueStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await KeyValueStore.create();
    directory = await Directory.systemTemp.createTemp('scan-ar-widget-');
    reader = ArTestReader();
    client = ArTestClient(directory);
    session = ScanPageCoordinator(
      scanner: ArTestScanner(),
      client: client,
      player: ArTestPlayer(),
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await session.close();
    await directory.delete(recursive: true);
  });

  Future<void> waitForArReturn() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (session.arBusy) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('AR did not return');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> driveUntil(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
      // Scan cleanup uses real file I/O; Riverpod/frame work uses the test zone.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool arEnabled = true,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => session.scan('profile'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          childProfileProvider.overrideWith(() => _Profile(arEnabled)),
          storyReaderProvider.overrideWithValue(reader),
          ttsTemporaryDirectoryProvider.overrideWithValue(() => directory),
        ],
        child: MaterialApp(
          theme: AppTheme.day(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScanAnyPageScreen(coordinator: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ready scan opens dinosaur directly without a picker', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Listen'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('scan.seeInAr')));
      await reader.opened.future.timeout(const Duration(seconds: 5));
      await waitForArReturn();
    });
    await tester.pumpAndSettle();
    expect(find.text('Choose your AR friend'), findsNothing);
    expect(reader.opens, 1);
    expect(reader.character!.assetBaseName, 'little_buddy');
    expect(find.text('Listen'), findsOneWidget);
    expect(session.canOpenAr, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new scan enters preparing AR without Listen or See in AR taps', (
    tester,
  ) async {
    final automatic = _AutomaticReader();
    reader = automatic;
    await pump(tester);
    addTearDown(() => automatic.closePreparing('test'));
    await tester.runAsync(() => tester.tap(find.text('Scan another page')));
    await driveUntil(tester, () => automatic.narrationAttached.isCompleted);
    expect(automatic.opens, 1);
    expect(automatic.character!.assetBaseName, 'little_buddy');
    expect(
      client.audioCalls,
      2,
    ); // Initial fixture plus this fresh scan; no duplicate TTS.
    await tester.runAsync(() async {
      automatic.terminal.complete(
        const StoryReaderResult(
          terminalCode: 'cancelled',
          lastPageId: null,
          pagesRead: [],
        ),
      );
      await waitForArReturn();
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('new scan autoplays audio when parent has disabled AR', (
    tester,
  ) async {
    final automatic = _AutomaticReader();
    reader = automatic;
    await pump(tester, arEnabled: false);
    await tester.runAsync(() => tester.tap(find.text('Scan another page')));
    await driveUntil(tester, () => (session.player as ArTestPlayer).plays == 1);
    expect(automatic.opens, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct dinosaur entry hands approved audio to native reader', (
    tester,
  ) async {
    reader.openPending = Completer<StoryReaderResult>();
    addTearDown(() {
      if (!reader.openPending!.isCompleted) {
        reader.openPending!.complete(
          const StoryReaderResult(
            terminalCode: 'cancelled',
            lastPageId: null,
            pagesRead: [],
          ),
        );
      }
    });
    await pump(tester);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('scan.seeInAr'))),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await reader.opened.future.timeout(const Duration(seconds: 5));
    });
    expect(reader.character!.id, 'little_buddy');
    expect(reader.heardBytes, [
      [1, 2, 3],
      [2, 2, 3],
    ]);
    await tester.runAsync(() async {
      reader.openPending!.complete(
        const StoryReaderResult(
          terminalCode: 'cancelled',
          lastPageId: null,
          pagesRead: [],
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (session.arBusy) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('AR did not return');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Listen'), findsOneWidget);
    expect(client.audioCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported phone retains Listen without an AR action', (
    tester,
  ) async {
    reader.supported = false;
    await pump(tester);
    expect(find.byKey(const ValueKey('scan.seeInAr')), findsNothing);
    expect(find.text('Listen'), findsOneWidget);
    expect(reader.opens, 0);
  });

  testWidgets('parent disabling AR hides the entry point', (tester) async {
    await pump(tester, arEnabled: false);
    expect(find.byKey(const ValueKey('scan.seeInAr')), findsNothing);
    expect(find.text('Listen'), findsOneWidget);
  });

  testWidgets('blocked scan offers no AR or Listen', (tester) async {
    client.blocked = true;
    await pump(tester);
    expect(find.byKey(const ValueKey('scan.seeInAr')), findsNothing);
    expect(find.text('Listen'), findsNothing);
  });

  testWidgets('Vietnamese controls fit a small phone', (tester) async {
    await pump(tester, locale: const Locale('vi'), size: const Size(320, 568));
    expect(find.byKey(const ValueKey('scan.seeInAr')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android entry uses the production dinosaur without selection', (
    tester,
  ) async {
    await pump(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('scan.seeInAr')));
      await reader.opened.future.timeout(const Duration(seconds: 5));
      await waitForArReturn();
    });
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(reader.character!.assetBaseName, 'little_buddy');
    expect(
      File('android/app/src/main/assets/little_buddy.glb').existsSync(),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
    'native failure shows a recoverable message without losing Listen',
    (tester) async {
      reader.failure = 'model_load_failed';
      await pump(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('scan.seeInAr'))),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await reader.opened.future.timeout(const Duration(seconds: 5));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (session.arBusy) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('AR failure did not settle');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('AR is not ready'), findsOneWidget);
      await tester.tap(find.text('Keep reading'));
      await tester.pumpAndSettle();
      expect(find.text('Listen'), findsOneWidget);
      expect(session.canOpenAr, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
