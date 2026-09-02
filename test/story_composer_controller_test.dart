import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/di.dart';
import 'package:storybook_ar/data/models/models.dart';
import 'package:storybook_ar/data/repositories/authored_story_repository.dart';
import 'package:storybook_ar/features/scan_any_page/native_scan_service.dart';
import 'package:storybook_ar/features/story_composer/story_composer_controller.dart';
import 'package:storybook_ar/features/story_composer/story_draft.dart';

class _FakeScanService implements ScanService {
  _FakeScanService(this.responses);

  final List<Object> responses;
  var calls = 0;

  @override
  Future<String> scanAndRecognize() async {
    final response = responses[calls++];
    if (response is Exception) throw response;
    return response as String;
  }
}

class _SlowScanService implements ScanService {
  final completer = Completer<String>();

  @override
  Future<String> scanAndRecognize() => completer.future;
}

class _FakeRepo implements AuthoredStoryRepository {
  _FakeRepo({this.failure});

  final AuthoredStoryFailure? failure;
  StoryDraft? saved;
  var calls = 0;

  @override
  Future<Story> createStory(StoryDraft draft) async {
    calls++;
    if (failure != null) throw failure!;
    saved = draft;
    return const Story(
        id: 'new', title: 'T', slug: 'authored-x', isAuthored: true);
  }

  @override
  Future<void> deleteStory(String storyId) async {}
}

void main() {
  StoryComposerDependencies deps(
    ScanService scan,
    AuthoredStoryRepository repo, {
    String language = 'en',
  }) =>
      (scanService: scan, repository: repo, languageCode: language);

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('addPage appends the recognized text', () async {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one']), _FakeRepo()));

    await c.read(provider.notifier).addPage();

    final state = c.read(provider);
    expect(state.phase, StoryComposerPhase.editing);
    expect(state.draft.pages.single.text, 'page one');
  });

  test('a cancelled scan keeps existing pages and shows no error', () async {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one', ScanCancelled()]), _FakeRepo()));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();

    final state = c.read(provider);
    expect(state.phase, StoryComposerPhase.editing);
    expect(state.failureCode, isNull);
    expect(state.draft.pages, hasLength(1));
  });

  test('a failed scan surfaces a scan: code and keeps the draft', () async {
    final c = container();
    final provider = storyComposerControllerProvider(deps(
        _FakeScanService(['page one', const ScanFailure('no_text')]),
        _FakeRepo()));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();

    final state = c.read(provider);
    expect(state.phase, StoryComposerPhase.failure);
    expect(state.failureCode, 'scan:no_text');
    expect(state.draft.pages, hasLength(1));
  });

  test('draft is not saveable without a title or without pages', () async {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['page one']), _FakeRepo()));
    final notifier = c.read(provider.notifier);

    expect(c.read(provider).draft.isSaveable, isFalse);
    notifier.setTitle('My Book');
    expect(c.read(provider).draft.isSaveable, isFalse);
    await notifier.addPage();
    expect(c.read(provider).draft.isSaveable, isTrue);
  });

  test('a whitespace-only title is not saveable', () {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService([]), _FakeRepo()));
    c.read(provider.notifier).setTitle('   ');
    expect(c.read(provider).draft.isSaveable, isFalse);
  });

  test('editPageText changes only the named page', () async {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['one', 'two']), _FakeRepo()));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();
    final firstId = c.read(provider).draft.pages.first.localId;
    notifier.editPageText(firstId, 'corrected');

    final pages = c.read(provider).draft.pages;
    expect(pages.first.text, 'corrected');
    expect(pages.last.text, 'two');
  });

  test('removePage drops only the named page', () async {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService(['one', 'two']), _FakeRepo()));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    await notifier.addPage();
    final firstId = c.read(provider).draft.pages.first.localId;
    notifier.removePage(firstId);

    expect(c.read(provider).draft.pages.single.text, 'two');
  });

  test('language defaults to the injected profile language', () {
    final c = container();
    final provider = storyComposerControllerProvider(
        deps(_FakeScanService([]), _FakeRepo(), language: 'vi'));
    expect(c.read(provider).draft.languageCode, 'vi');
  });

  test('save failure keeps the draft and reports the code', () async {
    final c = container();
    final provider = storyComposerControllerProvider(deps(
      _FakeScanService(['one']),
      _FakeRepo(failure: const AuthoredStoryFailure('quota_reached')),
    ));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    notifier.acknowledgeDisclosure();
    await notifier.save();

    final state = c.read(provider);
    expect(state.phase, StoryComposerPhase.failure);
    expect(state.failureCode, 'save:quota_reached');
    expect(state.draft.pages, hasLength(1));
    expect(state.savedStoryId, isNull);
  });

  test('successful save records the new story id and sends the draft',
      () async {
    final c = container();
    final repo = _FakeRepo();
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService(['one']), repo));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    notifier.acknowledgeDisclosure();
    await notifier.save();

    expect(c.read(provider).savedStoryId, 'new');
    expect(repo.saved!.pages, hasLength(1));
    expect(repo.saved!.title, 'My Book');
  });

  test('save is a no-op when the draft is not saveable', () async {
    final c = container();
    final repo = _FakeRepo();
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService([]), repo));

    await c.read(provider.notifier).save();

    expect(repo.saved, isNull);
    expect(c.read(provider).phase, StoryComposerPhase.editing);
  });

  test('first save attempt is gated behind the cloud-storage disclosure',
      () async {
    final c = container();
    final repo = _FakeRepo();
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService(['one']), repo));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    await notifier.save();

    final state = c.read(provider);
    expect(state.disclosurePending, isTrue);
    expect(state.disclosureAcknowledged, isFalse);
    expect(state.phase, StoryComposerPhase.editing);
    expect(repo.calls, 0);
  });

  test('cancelling the disclosure keeps the draft and clears the prompt',
      () async {
    final c = container();
    final repo = _FakeRepo();
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService(['one']), repo));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    await notifier.save();
    notifier.cancelDisclosure();

    final state = c.read(provider);
    expect(state.disclosurePending, isFalse);
    expect(state.disclosureAcknowledged, isFalse);
    expect(state.phase, StoryComposerPhase.editing);
    expect(state.draft.pages, hasLength(1));
    expect(state.draft.title, 'My Book');
    expect(repo.calls, 0);
  });

  test('after confirming, later saves in the same flow proceed without '
      're-asking', () async {
    final c = container();
    final repo = _FakeRepo(
        failure: const AuthoredStoryFailure('privacy_policy_review_required'));
    final provider =
        storyComposerControllerProvider(deps(_FakeScanService(['one']), repo));
    final notifier = c.read(provider.notifier);

    await notifier.addPage();
    notifier.setTitle('My Book');
    await notifier.save();
    notifier.acknowledgeDisclosure();
    await notifier.save();

    var state = c.read(provider);
    expect(state.phase, StoryComposerPhase.failure);
    expect(state.failureCode, 'save:privacy_policy_review_required');
    expect(state.disclosurePending, isFalse);
    expect(repo.calls, 1);

    await notifier.save();

    state = c.read(provider);
    expect(state.failureCode, 'save:privacy_policy_review_required');
    expect(state.disclosurePending, isFalse);
    expect(repo.calls, 2);
  });

  test('a scan resolving after reset does not write into the new draft',
      () async {
    final c = container();
    final scan = _SlowScanService();
    final provider = storyComposerControllerProvider(deps(scan, _FakeRepo()));
    final notifier = c.read(provider.notifier);

    final pending = notifier.addPage();
    notifier.reset();
    scan.completer.complete('late text');
    await pending;

    expect(c.read(provider).draft.pages, isEmpty);
  });
}
