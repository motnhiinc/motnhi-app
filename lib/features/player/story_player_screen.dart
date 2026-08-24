import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/big_play_button.dart';
import '../../shared/widgets/storybook/storybook.dart';
import '../ar/ar_character.dart';
import '../ar/ar_character_providers.dart';
import '../ar/ar_preparing_dialog.dart';
import '../ar/ar_reader_controller.dart';
import '../ar/native_story_reader.dart';
import '../player/narration_audio_fetcher.dart';
import '../profile/profile_providers.dart';
import '../questions/question_sheet.dart';
import '../settings/settings_providers.dart';
import 'narration_player.dart';
import 'page_text_view.dart';
import 'player_providers.dart';

/// The main reading interface (§7.1.2). Loads the story, then hands off to a
/// stateful body whose lifecycle owns the narration engine and the session.
class StoryPlayerScreen extends ConsumerWidget {
  const StoryPlayerScreen({super.key, required this.storyId});

  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context)!;
    final detail = ref.watch(storyDetailProvider(storyId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: detail.when(
          loading: () => LoadingView(message: s.openingBook),
          error: (_, _) => ErrorView(
            message: s.couldNotOpenStory,
            onRetry: () => ref.invalidate(storyDetailProvider(storyId)),
          ),
          data: (d) => d == null
              ? ErrorView(message: s.storyNotFound)
              : _PlayerBody(detail: d),
        ),
      ),
    );
  }
}

class _PlayerBody extends ConsumerStatefulWidget {
  const _PlayerBody({required this.detail});

  final StoryDetail detail;

  @override
  ConsumerState<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends ConsumerState<_PlayerBody> {
  late final NarrationPlayer _player;

  /// Held rather than re-read: narrationAudioFetcherProvider is autoDispose and
  /// is read without a listener, so it is torn down after the first frame. A
  /// fresh read in the AR handler would build an empty-cache fetcher and
  /// re-issue a TTS request for every page.
  NarrationAudioFetcher? _fetcher;

  final PageController _pageController = PageController();
  int _pageIndex = 0;
  int _loadGeneration = 0;
  String? _sessionId;
  bool _storyCompleted = false;
  bool _storyReaderSupported = false;
  bool _arBusy = false;
  bool _suppressNextAutoplay = false;

  List<StoryPage> get _pages => widget.detail.orderedPages;
  Story get _story => widget.detail.story;

  @override
  void initState() {
    super.initState();
    // Curated stories play registered clips or the device-TTS fallback; only
    // authored stories generate narration per read. Without this gate, an
    // environment where register_assets.py never ran would silently turn
    // every curated page into an OpenAI call.
    _fetcher = _story.isAuthored
        ? ref.read(narrationAudioFetcherProvider(_story.id))
        : null;
    _player = NarrationPlayer(
      resolver: ref.read(assetUrlResolverProvider),
      fetcher: _fetcher,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
      _loadPage(0, autoplay: false);
      _player.isComplete.addListener(_onMaybeComplete);
      _resolveArSupport();
    });
  }

  /// Asked once, before any AR button is shown, so an unsupported device never
  /// offers AR and then fails after a multi-second narration preparation.
  Future<void> _resolveArSupport() async {
    final supported = await ref.read(storyReaderProvider).isSupported();
    if (!mounted || supported == _storyReaderSupported) return;
    setState(() => _storyReaderSupported = supported);
  }

  Future<void> _startSession() async {
    final profile = ref.read(childProfileProvider).value;
    final bedtime = ref.read(bedtimeModeProvider);
    final session = await ref.read(sessionRepositoryProvider).startSession(
          childProfileId: profile?.id ?? 'local',
          storyId: _story.id,
          mode: bedtime ? SessionMode.bedtime : SessionMode.library,
        );
    if (mounted) _sessionId = session.id;
  }

  double _effectiveSpeed() {
    final settings = ref.read(settingsProvider).value;
    final bedtime = ref.read(bedtimeModeProvider);
    var speed = settings?.voiceSpeed ?? 1.0;
    if (bedtime) speed *= 0.85; // calmer pacing (§7.1.6)
    return speed;
  }

  /// Fired per page turn without being awaited, so everything after an await
  /// must re-check the generation: for an authored story the load contains a
  /// multi-second narration fetch, and a stale continuation would regress
  /// last_page_number and start playback for the page the reader just left.
  Future<void> _loadPage(int index, {required bool autoplay}) async {
    final generation = ++_loadGeneration;
    final page = _pages[index];
    await _player.load(
      widget.detail.segmentsForPage(page.id),
      speedMultiplier: _effectiveSpeed(),
      languageCode: _story.languageCode,
    );
    if (!mounted || generation != _loadGeneration) return;

    final sid = _sessionId;
    if (sid != null) {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.updateLastPage(sid, page.pageNumber);
      if (!mounted || generation != _loadGeneration) return;
      await repo.recordEvent(
        sessionId: sid,
        eventType: 'page_viewed',
        pageId: page.id,
        payload: {'page_number': page.pageNumber},
      );
      if (!mounted || generation != _loadGeneration) return;
    }
    if (autoplay) await _player.play();
  }

  void _onPageChanged(int index) {
    setState(() => _pageIndex = index);
    // Suppressed for exactly one turn when returning from AR, so the app does
    // not immediately re-narrate the page the character just finished reading.
    final autoplay = !_suppressNextAutoplay;
    _suppressNextAutoplay = false;
    _loadPage(index, autoplay: autoplay);
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _exitToSafety() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// Lets the reader pick which character joins them in AR. Dismissing the
  /// sheet without a choice means "no AR": we return quietly with the player
  /// still paused, and no error dialog for what is simply a change of mind.
  Future<ArCharacter?> _chooseArCharacter() {
    final s = AppLocalizations.of(context)!;
    final selected = ref.read(selectedArCharacterProvider);
    return showModalBottomSheet<ArCharacter>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        // shrinkWrap + Flexible: the list takes its natural height when there
        // is room, and scrolls instead of overflowing on short/landscape
        // screens where seven rows cannot fit.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                s.chooseArFriend,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final character in arCharacters)
                    ListTile(
                      leading: const Icon(Icons.toys_rounded),
                      title: Text(character.displayName),
                      trailing: character.id == selected.id
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(character),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openArReader() async {
    if (_arBusy) return;
    _arBusy = true;
    try {
      await _player.pause();
      if (!mounted) return;

      final character = await _chooseArCharacter();
      if (!mounted || character == null) return;

      // Persisted before AR opens on purpose: an attempt that later fails must
      // not throw away the reader's choice — the same friend is preselected
      // next time.
      await ref.read(selectedArCharacterProvider.notifier).select(character);
      if (!mounted) return;

      final controller = ArReaderController(
        detail: widget.detail,
        reader: ref.read(storyReaderProvider),
        character: character,
        resolver: ref.read(assetUrlResolverProvider),
        fetcher: _fetcher,
        tts: ref.read(ttsFileSynthesizerProvider),
        downloader: ref.read(arAudioDownloaderProvider),
        // Android's Directory.systemTemp is the app's code_cache dir, which is a
        // *sibling* of the cacheDir the native AudioPathValidator allows, so every
        // clip written there fails containment and AR returns audio_missing. This is
        // the same platform split main.dart already applies to TTS; on iOS the
        // provider is null and systemTemp (NSTemporaryDirectory) is correct.
        directory:
            ref.read(ttsTemporaryDirectoryProvider)?.call() ?? Directory.systemTemp,
        initialPageIndex: _pageIndex,
      );

      final result = await showArPreparingDialog(context, controller: controller);
      if (!mounted) return;

      if (result == null) {
        await _showArFailure(controller.value.failureCode ?? 'ar_failed');
        return;
      }
      await _onArReturned(result);
    } finally {
      _arBusy = false;
    }
  }

  Future<void> _onArReturned(StoryReaderResult result) async {
    // Pages read inside AR never pass through _loadPage, so without this the
    // session and the parent dashboard would undercount them.
    final sessionId = _sessionId;
    if (sessionId != null && result.pagesRead.isNotEmpty) {
      final repository = ref.read(sessionRepositoryProvider);
      for (final pageId in result.pagesRead) {
        final page = _pages.where((p) => p.id == pageId).firstOrNull;
        if (page == null) continue;
        await repository.recordEvent(
          sessionId: sessionId,
          eventType: 'page_viewed',
          pageId: page.id,
          payload: {'page_number': page.pageNumber, 'mode': 'ar'},
        );
        if (!mounted) return;
      }
    }

    final lastPageId = result.lastPageId;
    if (lastPageId == null) return;
    final index = _pages.indexWhere((p) => p.id == lastPageId);
    if (index < 0 || index == _pageIndex) return;

    _suppressNextAutoplay = true;
    _goToPage(index);
  }

  /// AR is an enhancement; losing it must never block reading, so every branch
  /// keeps the child in the book.
  Future<void> _showArFailure(String code) async {
    // A reader is already open — never a child-facing condition.
    if (code == 'reader_in_progress') return;

    final s = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.arNotReadyTitle),
        content: Text(_arFailureMessage(s, code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.keepReading),
          ),
          if (code != 'ar_unsupported')
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openArReader();
              },
              child: Text(s.retry),
            ),
        ],
      ),
    );
  }

  static String _arFailureMessage(AppLocalizations s, String code) {
    switch (code) {
      case 'narration_unavailable':
        return s.arErrNarration;
      case 'ar_unsupported':
        return s.arErrUnsupported;
      case 'ar_unavailable':
      case 'ar_failed':
        return s.arErrStart;
      case 'model_missing':
      case 'model_load_failed':
        return s.arErrModel;
      case 'audio_missing':
      case 'audio_failed':
        return s.arErrAudio;
      default:
        return s.arErrGeneric;
    }
  }

  void _onMaybeComplete() {
    if (_player.isComplete.value &&
        _pageIndex == _pages.length - 1 &&
        !_storyCompleted) {
      _storyCompleted = true;
      _completeStory();
    }
  }

  Future<void> _completeStory() async {
    final sid = _sessionId;
    if (sid != null) {
      await ref.read(sessionRepositoryProvider).completeSession(sid);
    }
    if (!mounted) return;
    final s = AppLocalizations.of(context)!;
    // Ask the story's questions, then a calm "well done" (no autoplay onward).
    await showStoryQuestions(
      context,
      ref,
      detail: widget.detail,
      sessionId: sid,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.theEndTitle),
        content: Text(s.whatALovelyStory),
        actions: [
          FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: Text(s.backToHome),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _player.isComplete.removeListener(_onMaybeComplete);
    _player.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final page = _pages[_pageIndex];
    final profile = ref.watch(childProfileProvider).value;
    // No longer gated on an ar_scenes row: every story opens the native reader,
    // so the only questions are whether the parent allows AR and the device can
    // actually do it.
    final arAvailable = (profile?.arEnabled ?? true) && _storyReaderSupported;
    final hasQuestions = widget.detail.questionsForPage(page.id).isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _exitToSafety,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.paper,
                        border: Border.all(color: t.line),
                      ),
                      child:
                          Icon(Icons.arrow_back_rounded, size: 20, color: t.ink),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          s.pageTitle(
                            page.pageNumber,
                            _pages.last.pageNumber,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        ref.read(bedtimeModeProvider.notifier).toggle(),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.paper,
                        border: Border.all(color: t.line),
                      ),
                      child: Icon(Icons.dark_mode_rounded,
                          size: 19, color: t.lavender),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _player.usingTtsFallback,
            builder: (_, usingTts, _) => usingTts
                ? Material(
                    color: t.gold.withValues(alpha: .3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 12),
                      child: Text(
                        s.ttsFallbackBanner,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _pages.length,
              itemBuilder: (_, i) => _StoryPageView(
                page: _pages[i],
                detail: widget.detail,
                player: _player,
                isActive: i == _pageIndex,
                arAvailable: arAvailable,
                onTapSegment: (segIndex) => _player.seekToSegment(segIndex),
              ),
            ),
          ),
          _PlayerControls(
            player: _player,
            pageIndex: _pageIndex,
            pageCount: _pages.length,
            arAvailable: arAvailable,
            hasQuestions: hasQuestions,
            onPrev: () => _goToPage(_pageIndex - 1),
            onNext: () => _goToPage(_pageIndex + 1),
            onAr: _openArReader,
            onQuestions: () => showPageQuestions(
              context,
              ref,
              detail: widget.detail,
              pageId: page.id,
              sessionId: _sessionId,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryPageView extends StatelessWidget {
  const _StoryPageView({
    required this.page,
    required this.detail,
    required this.player,
    required this.isActive,
    required this.arAvailable,
    required this.onTapSegment,
  });

  final StoryPage page;
  final StoryDetail detail;
  final NarrationPlayer player;
  final bool isActive;
  final bool arAvailable;
  final ValueChanged<int> onTapSegment;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;
    final segments = detail.segmentsForPage(page.id);
    final hasArSurprise = arAvailable && detail.arSceneForPage(page.id) != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              child: _PageIllustration(page: page),
            ),
          ),
          if (hasArSurprise)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: t.gold.withValues(alpha: .32),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('✦',
                      style: TextStyle(
                          fontSize: 13, color: t.coralDeep)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      s.arSurpriseBanner,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.sansFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          PageTextView(
            segments: segments,
            player: player,
            isActivePage: isActive,
            onTapSegment: onTapSegment,
          ),
        ],
      ),
    );
  }
}

class _PageIllustration extends StatelessWidget {
  const _PageIllustration({required this.page});

  final StoryPage page;

  @override
  Widget build(BuildContext context) {
    final asset = page.pageImageAssetId;
    final t = context.stitch;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(t),
      );
    }
    return _placeholder(t);
  }

  Widget _placeholder(StitchTokens t) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.lavenderContainer.withValues(alpha: .45),
              t.paper,
            ],
          ),
        ),
        child: Center(
          child: Text('✦',
              style: TextStyle(fontSize: 44, color: t.lavender)),
        ),
      );
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.player,
    required this.pageIndex,
    required this.pageCount,
    required this.arAvailable,
    required this.hasQuestions,
    required this.onPrev,
    required this.onNext,
    required this.onAr,
    required this.onQuestions,
  });

  final NarrationPlayer player;
  final int pageIndex;
  final int pageCount;
  final bool arAvailable;
  final bool hasQuestions;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onAr;
  final VoidCallback onQuestions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final t = context.stitch;

    Widget circle({
      required IconData icon,
      required String tooltip,
      VoidCallback? onTap,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: t.paper,
          side: BorderSide(color: t.line),
        ),
        iconSize: 22,
        icon: Icon(icon, color: onTap == null ? t.inkMuted : t.ink),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          children: [
            ProgressBeads(
              count: pageCount,
              currentIndex: pageIndex,
              alignment: WrapAlignment.center,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                circle(
                  icon: Icons.replay_rounded,
                  tooltip: s.replayPage,
                  onTap: player.replay,
                ),
                circle(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '',
                  onTap: pageIndex > 0 ? onPrev : null,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: player.isLoading,
                  builder: (_, loading, _) => ValueListenableBuilder<bool>(
                    valueListenable: player.isPlaying,
                    builder: (_, playing, _) => BigPlayButton(
                      isPlaying: playing,
                      // Disabled while a clip is being fetched: a tap here would
                      // otherwise start device TTS a moment before it lands.
                      onPressed: loading
                          ? null
                          : () => playing ? player.pause() : player.play(),
                    ),
                  ),
                ),
                circle(
                  icon: Icons.chevron_right_rounded,
                  tooltip: '',
                  onTap: pageIndex < pageCount - 1 ? onNext : null,
                ),
                if (arAvailable)
                  circle(
                    icon: Icons.view_in_ar_rounded,
                    tooltip: s.seeInAr,
                    onTap: onAr,
                  )
                else
                  circle(
                    icon: Icons.quiz_outlined,
                    tooltip: hasQuestions ? s.questionLabel : '',
                    onTap: hasQuestions ? onQuestions : null,
                  ),
              ],
            ),
            if (arAvailable) ...[
              const SizedBox(height: 12),
              PressablePillButton(
                label: s.magicSpark,
                icon: Icons.auto_awesome_rounded,
                height: 46,
                variant: PillVariant.secondary,
                onPressed: onAr,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
