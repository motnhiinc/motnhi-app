import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:storybook_ar/features/ar/ar_character.dart';
import 'package:storybook_ar/features/ar/ar_narration_bundle.dart';
import 'package:storybook_ar/features/ar/native_story_reader.dart';
import 'package:storybook_ar/features/scan_any_page/line_audio_player.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/scan_any_page/page_validation_client.dart';
import 'package:storybook_ar/features/scan_any_page/scanned_page.dart';

class ArTestScanner implements ScanService {
  @override
  Future<ScannedPage> scanAndRecognize() async => ScannedPage(
    // Valid 1x1 transparent PNG for widget decoding; production capture is JPEG.
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
    ),
    1,
    1,
    const [ScannedLine('One.', 0, 0, 1, .4), ScannedLine('Two.', 0, .5, 1, .4)],
  );
}

class ArTestClient implements PageReadingClient {
  ArTestClient(this.directory);
  final Directory directory;
  int validations = 0, audioCalls = 0;
  bool blocked = false;
  final files = <File>[];
  @override
  Future<PageValidationResult> validate(
    ScannedPage page,
    String profileId, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    validations++;
    return blocked
        ? const PageValidationResult.blocked('content_unsuitable')
        : const PageValidationResult.approved('approved');
  }

  @override
  Future<List<File>> prepareAudio(
    String proof,
    String profileId,
    List<String> lines, {
    String? contentLanguage,
    CancelToken? cancelToken,
    String? attemptId,
    String? operationId,
  }) async {
    audioCalls++;
    final clips = <File>[];
    for (var i = 0; i < lines.length; i++) {
      final file = await File(
        '${directory.path}/original-$audioCalls-$i.mp3',
      ).writeAsBytes([i + 1, 2, 3]);
      files.add(file);
      clips.add(file);
    }
    return clips;
  }

  @override
  Future<void> dispose() async {}
}

class ArTestPlayer implements ScanPagePlayer {
  @override
  final currentLine = ValueNotifier(0);
  @override
  final playing = ValueNotifier(false);
  @override
  final completed = ValueNotifier(false);
  int plays = 0, pauses = 0;
  @override
  Future<void> load(List<File> files) async {
    completed.value = false;
  }

  @override
  Future<void> play() async {
    plays++;
    playing.value = true;
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing.value = false;
  }

  @override
  Future<void> resume() => play();
  @override
  Future<void> replay() => play();
  @override
  Future<void> stop() async {
    playing.value = false;
  }

  @override
  Future<void> dispose() async {}
}

class ArTestReader implements StoryReader {
  bool supported = true;
  String? failure;
  int opens = 0;
  Completer<StoryReaderSupport>? supportPending;
  Completer<StoryReaderResult>? openPending;
  final opened = Completer<void>();
  List<ArNarrationPage> pages = [];
  ArCharacter? character;
  List<List<int>> heardBytes = [];
  @override
  Future<StoryReaderSupport> isSupported() async => supportPending != null
      ? await supportPending!.future
      : StoryReaderSupport(supported: supported);
  @override
  Future<StoryReaderResult> open({
    required List<ArNarrationPage> pages,
    required int initialPageIndex,
    required ArCharacter character,
  }) async {
    opens++;
    this.pages = pages;
    this.character = character;
    for (final path in pages.single.audioFilePaths) {
      heardBytes.add(await File(path).readAsBytes());
    }
    if (!opened.isCompleted) opened.complete();
    if (failure != null) throw StoryReaderFailure(failure!);
    return openPending != null
        ? await openPending!.future
        : const StoryReaderResult(
            terminalCode: 'cancelled',
            lastPageId: null,
            pagesRead: [],
          );
  }
}
