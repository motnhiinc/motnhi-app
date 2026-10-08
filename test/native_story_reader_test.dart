import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('storybook_ar/character_reader');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  void stub(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() => calls = <MethodCall>[]);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const pages = [
    ArNarrationPage(
      pageId: 'p1',
      pageNumber: 1,
      audioFilePaths: ['/tmp/ar_s_p1_s0.mp3', '/tmp/ar_s_p1_s1.mp3'],
    ),
    ArNarrationPage(
      pageId: 'p2',
      pageNumber: 2,
      audioFilePaths: ['/tmp/ar_s_p2_s0.wav'],
    ),
  ];

  const character = ArCharacter(
    id: 'cute_doll_v03',
    displayName: 'Doll 3',
    assetBaseName: 'cute_doll_v03',
  );

  const foxCharacter = ArCharacter(
    id: 'fox_default',
    displayName: 'Fox',
    assetBaseName: 'scan_any_page_character',
  );

  group('isSupported', () {
    test('parses support and diagnostic metadata', () async {
      stub((_) async => {
            'supported': false,
            'diagnostics': {
              'availability': 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
              'decision': 'Unsupported',
            },
          });
      final support = await NativeStoryReader().isSupported();

      expect(support.supported, isFalse);
      expect(
          support.diagnostic?.availability, 'UNSUPPORTED_DEVICE_NOT_CAPABLE');
      expect(support.diagnostic?.decision, 'Unsupported');
    });

    test('accepts a legacy Boolean response', () async {
      stub((_) async => true);
      final support = await NativeStoryReader().isSupported();

      expect(support.supported, isTrue);
      expect(support.diagnostic, isNull);
    });

    test('is false when the platform errors or has no implementation',
        () async {
      stub((_) async => throw PlatformException(code: 'boom'));
      expect((await NativeStoryReader().isSupported()).supported, isFalse);

      messenger.setMockMethodCallHandler(channel, null);
      expect((await NativeStoryReader().isSupported()).supported, isFalse);
    });

    test('is false when the channel answers null', () async {
      stub((_) async => null);
      expect((await NativeStoryReader().isSupported()).supported, isFalse);
    });
  });

  group('open', () {
    test(
      'scan mode requests automatic reading and returns explicit next scan',
      () async {
        stub((_) async => {'terminalCode': 'scan_next'});
        final result = await NativeStoryReader().open(
          pages: [pages.first],
          initialPageIndex: 0,
          character: character,
          scannedPageMode: true,
        );
        expect((calls.single.arguments as Map)['scannedPageMode'], isTrue);
        expect(result.scanNextRequested, isTrue);
        expect(result.completed, isFalse);
      },
    );

    test('sends every page and clip in the native wire shape', () async {
      stub((_) async => {
            'terminalCode': 'completed',
            'lastPageId': 'p2',
            'pagesRead': ['p1', 'p2'],
          });

      await NativeStoryReader().open(
        pages: pages,
        initialPageIndex: 1,
        character: character,
      );

      expect(calls.single.method, 'openStoryReader');
      final arguments = calls.single.arguments as Map;
      expect(arguments['initialPageIndex'], 1);
      expect(arguments['characterId'], 'cute_doll_v03');
      expect(arguments['modelAssetBaseName'], 'cute_doll_v03');
      expect(arguments.containsKey('scannedPageMode'), isFalse);
      expect(arguments['pages'], [
        {
          'pageId': 'p1',
          'pageNumber': 1,
          'audioFilePaths': ['/tmp/ar_s_p1_s0.mp3', '/tmp/ar_s_p1_s1.mp3'],
        },
        {
          'pageId': 'p2',
          'pageNumber': 2,
          'audioFilePaths': ['/tmp/ar_s_p2_s0.wav'],
        },
      ]);
    });

    test('sends a different character as its own id and base name pair',
        () async {
      stub((_) async => {'terminalCode': 'completed'});

      await NativeStoryReader().open(
        pages: pages,
        initialPageIndex: 0,
        character: foxCharacter,
      );

      final arguments = calls.single.arguments as Map;
      expect(arguments['characterId'], 'fox_default');
      expect(arguments['modelAssetBaseName'], 'scan_any_page_character');
    });

    test('parses a completed result', () async {
      stub((_) async => {
            'terminalCode': 'completed',
            'lastPageId': 'p2',
            'pagesRead': ['p1', 'p2'],
          });

      final result = await NativeStoryReader()
          .open(pages: pages, initialPageIndex: 0, character: character);

      expect(result.terminalCode, 'completed');
      expect(result.completed, isTrue);
      expect(result.lastPageId, 'p2');
      expect(result.pagesRead, ['p1', 'p2']);
    });

    test('parses a cancelled result, which is not a failure', () async {
      stub((_) async => {
            'terminalCode': 'cancelled',
            'lastPageId': 'p1',
            'pagesRead': ['p1'],
          });

      final result = await NativeStoryReader()
          .open(pages: pages, initialPageIndex: 0, character: character);

      expect(result.terminalCode, 'cancelled');
      expect(result.completed, isFalse);
      expect(result.lastPageId, 'p1');
    });

    test('tolerates a null lastPageId and a missing pagesRead', () async {
      stub((_) async => {'terminalCode': 'cancelled', 'lastPageId': null});

      final result = await NativeStoryReader()
          .open(pages: pages, initialPageIndex: 0, character: character);

      expect(result.lastPageId, isNull);
      expect(result.pagesRead, isEmpty);
    });

    test('maps a PlatformException to StoryReaderFailure with its code',
        () async {
      stub((_) async => throw PlatformException(code: 'model_missing'));

      expect(
        () => NativeStoryReader()
            .open(pages: pages, initialPageIndex: 0, character: character),
        throwsA(isA<StoryReaderFailure>()
            .having((e) => e.code, 'code', 'model_missing')),
      );
    });

    test('preserves ARCore details from PlatformException', () async {
      stub((_) async => throw PlatformException(
            code: 'ar_unsupported',
            details: {
              'availability': 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
              'decision': 'Unsupported',
              'cause': 'UnavailableDeviceNotCompatibleException',
            },
          ));

      try {
        await NativeStoryReader().open(
          pages: pages,
          initialPageIndex: 0,
          character: character,
        );
        fail('expected StoryReaderFailure');
      } on StoryReaderFailure catch (error) {
        expect(error.code, 'ar_unsupported');
        expect(
            error.diagnostic?.availability, 'UNSUPPORTED_DEVICE_NOT_CAPABLE');
        expect(error.diagnostic?.decision, 'Unsupported');
        expect(
            error.diagnostic?.cause, 'UnavailableDeviceNotCompatibleException');
      }
    });

    test('maps a missing implementation to a failure rather than hanging',
        () async {
      messenger.setMockMethodCallHandler(channel, null);

      expect(
        () => NativeStoryReader()
            .open(pages: pages, initialPageIndex: 0, character: character),
        throwsA(isA<StoryReaderFailure>()),
      );
    });
  });
}
