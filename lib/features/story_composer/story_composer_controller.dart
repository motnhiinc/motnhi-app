import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/authored_story_repository.dart';
import '../scan_any_page/native_scan_service.dart';
import 'story_draft.dart';

enum StoryComposerPhase { editing, scanning, saving, failure }

class StoryComposerState {
  const StoryComposerState({
    this.phase = StoryComposerPhase.editing,
    this.draft = const StoryDraft(),
    this.failureCode,
    this.savedStoryId,
    this.disclosureAcknowledged = false,
    this.disclosurePending = false,
  });

  final StoryComposerPhase phase;
  final StoryDraft draft;
  final String? failureCode;
  final String? savedStoryId;

  /// Cloud-storage disclosure state (§14.3): per-flow widget/controller state
  /// only — never persisted. A fresh composer flow must confirm the
  /// "stored in the app cloud" disclosure once before the first save.
  final bool disclosureAcknowledged;

  /// True while the first save attempt is waiting on the disclosure dialog.
  final bool disclosurePending;

  StoryComposerState copyWith({
    StoryComposerPhase? phase,
    StoryDraft? draft,
    Object? failureCode = _unset,
    Object? savedStoryId = _unset,
    bool? disclosureAcknowledged,
    bool? disclosurePending,
  }) {
    return StoryComposerState(
      phase: phase ?? this.phase,
      draft: draft ?? this.draft,
      failureCode: identical(failureCode, _unset)
          ? this.failureCode
          : failureCode as String?,
      savedStoryId: identical(savedStoryId, _unset)
          ? this.savedStoryId
          : savedStoryId as String?,
      disclosureAcknowledged:
          disclosureAcknowledged ?? this.disclosureAcknowledged,
      disclosurePending: disclosurePending ?? this.disclosurePending,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StoryComposerState &&
        other.phase == phase &&
        other.draft == draft &&
        other.failureCode == failureCode &&
        other.savedStoryId == savedStoryId &&
        other.disclosureAcknowledged == disclosureAcknowledged &&
        other.disclosurePending == disclosurePending;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    draft,
    failureCode,
    savedStoryId,
    disclosureAcknowledged,
    disclosurePending,
  );
}

const _unset = Object();

typedef StoryComposerDependencies = ({
  ScanService scanService,
  AuthoredStoryRepository repository,
  String languageCode,
});

/// Owns the multi-page draft for a captured story.
///
/// Deliberately not an extension of `ScanAnyPageController`: that one is
/// single-shot and welded to the TTS + AR reader lifecycle. This reuses only
/// [ScanService], the piece the two genuinely share.
class StoryComposerController extends Notifier<StoryComposerState> {
  StoryComposerController({
    required ScanService scanService,
    required AuthoredStoryRepository repository,
    required String languageCode,
  }) : _scanService = scanService,
       _repository = repository,
       _languageCode = languageCode;

  final ScanService _scanService;
  final AuthoredStoryRepository _repository;
  final String _languageCode;

  var _generation = 0;
  var _disposed = false;
  var _nextLocalId = 0;

  @override
  StoryComposerState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    return StoryComposerState(draft: StoryDraft(languageCode: _languageCode));
  }

  void setTitle(String title) =>
      state = state.copyWith(draft: state.draft.copyWith(title: title));

  void setLanguage(String languageCode) => state = state.copyWith(
    draft: state.draft.copyWith(languageCode: languageCode),
  );

  void editPageText(String localId, String text) {
    final pages = [
      for (final page in state.draft.pages)
        page.localId == localId ? page.copyWith(text: text) : page,
    ];
    state = state.copyWith(draft: state.draft.copyWith(pages: pages));
  }

  void removePage(String localId) {
    final pages = state.draft.pages.where((p) => p.localId != localId).toList();
    state = state.copyWith(draft: state.draft.copyWith(pages: pages));
  }

  Future<void> addPage() async {
    final generation = ++_generation;
    state = state.copyWith(
      phase: StoryComposerPhase.scanning,
      failureCode: null,
    );
    try {
      final page = await _scanService.scanAndRecognize();
      if (!_isCurrent(generation)) return;
      final pages = [
        ...state.draft.pages,
        DraftPage(localId: 'p${_nextLocalId++}', text: page.joinedText),
      ];
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        draft: state.draft.copyWith(pages: pages),
        failureCode: null,
      );
    } on ScanCancelled {
      if (!_isCurrent(generation)) return;
      // Backing out of the scanner is not an error; keep what we have.
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        failureCode: null,
      );
    } on ScanFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'scan:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'scan:unknown',
      );
    }
  }

  /// Parent confirmed the cloud-storage disclosure for this flow. Never
  /// persisted — a fresh flow asks again.
  void acknowledgeDisclosure() => state = state.copyWith(
    disclosureAcknowledged: true,
    disclosurePending: false,
    failureCode: null,
  );

  /// Parent cancelled the disclosure; the draft stays as-is.
  void cancelDisclosure() => state = state.copyWith(disclosurePending: false);

  Future<void> save() async {
    if (!state.draft.isSaveable) return;
    // First save attempt in a fresh flow is gated behind the cloud-storage
    // disclosure (§14.3); the screen shows the dialog when [disclosurePending]
    // flips true.
    if (!state.disclosureAcknowledged) {
      state = state.copyWith(disclosurePending: true);
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(phase: StoryComposerPhase.saving, failureCode: null);
    try {
      final story = await _repository.createStory(state.draft);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.editing,
        failureCode: null,
        savedStoryId: story.id,
      );
    } on AuthoredStoryFailure catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'save:${error.code}',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        phase: StoryComposerPhase.failure,
        failureCode: 'save:unknown',
      );
    }
  }

  void reset() {
    _generation++;
    state = StoryComposerState(draft: StoryDraft(languageCode: _languageCode));
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}
