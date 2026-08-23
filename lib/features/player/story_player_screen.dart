import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/big_play_button.dart';
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
    final detail = ref.watch(storyDetailProvider(storyId));
    return Scaffold(
      body: detail.when(
        loading: () => const LoadingView(message: 'Opening the book…'),
        error: (_, _) => ErrorView(
          message: "We couldn't open this story.",
          onRetry: () => ref.invalidate(storyDetailProvider(storyId)),
        ),
        data: (d) => d == null
            ? const ErrorView(message: 'Story not found.')
            : _PlayerBody(detail: d),
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

  Future<void> _openArReader() async {
    if (_arBusy) return;
    _arBusy = true;
    try {
      await _player.pause();
      if (!mounted) return;

      final controller = ArReaderController(
        detail: widget.detail,
        reader: ref.read(storyReaderProvider),
        resolver: ref.read(assetUrlResolverProvider),
        fetcher: _fetcher,
        tts: ref.read(ttsFileSynthesizerProvider),
        downloader: ref.read(arAudioDownloaderProvider),
        directory: Directory.systemTemp,
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AR is not ready'),
        content: Text(_arFailureMessage(code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep reading'),
          ),
          if (code != 'ar_unsupported')
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openArReader();
              },
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }

  static String _arFailureMessage(String code) {
    switch (code) {
      case 'narration_unavailable':
        return "We couldn't get this story's voice ready for AR. You can keep "
            'reading here and try again later.';
      case 'ar_unsupported':
        return 'This device cannot show the character in AR, but the story '
            'still reads here.';
      case 'ar_unavailable':
      case 'ar_failed':
        return "We couldn't start AR this time. Your story is still here.";
      case 'model_missing':
      case 'model_load_failed':
        return "The character couldn't load. Your story is still here.";
      case 'audio_missing':
      case 'audio_failed':
        return "The character couldn't play this story's voice. You can keep "
            'reading here.';
      default:
        return "We couldn't open the character reader. Your story is still "
            'here.';
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
        title: const Text('The End 🌟'),
        content: const Text('What a lovely story!'),
        actions: [
          FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Back to library'),
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
    final page = _pages[_pageIndex];
    final profile = ref.watch(childProfileProvider).value;
    // No longer gated on an ar_scenes row: every story opens the native reader,
    // so the only questions are whether the parent allows AR and the device can
    // actually do it.
    final arAvailable = (profile?.arEnabled ?? true) && _storyReaderSupported;
    final hasQuestions = widget.detail.questionsForPage(page.id).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_story.title),
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _player.usingTtsFallback,
              builder: (_, usingTts, _) =>
                  usingTts ? const _TtsFallbackBanner() : const SizedBox.shrink(),
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
    required this.onTapSegment,
  });

  final StoryPage page;
  final StoryDetail detail;
  final NarrationPlayer player;
  final bool isActive;
  final ValueChanged<int> onTapSegment;

  @override
  Widget build(BuildContext context) {
    final segments = detail.segmentsForPage(page.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _PageIllustration(page: page),
            ),
          ),
          const SizedBox(height: 20),
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
    final scheme = Theme.of(context).colorScheme;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(scheme),
      );
    }
    return _placeholder(scheme);
  }

  Widget _placeholder(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.secondaryContainer, scheme.surface],
          ),
        ),
        child: Center(
          child: Text('Page ${page.pageNumber}',
              style: TextStyle(color: scheme.onSecondaryContainer)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          // Page dots.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == pageIndex
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: pageIndex > 0 ? onPrev : null,
              ),
              IconButton(
                iconSize: 36,
                tooltip: 'Replay page',
                icon: const Icon(Icons.replay_rounded),
                onPressed: player.replay,
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
              if (arAvailable)
                IconButton(
                  iconSize: 36,
                  tooltip: 'See in AR',
                  icon: const Icon(Icons.view_in_ar_rounded),
                  onPressed: onAr,
                )
              else
                IconButton(
                  iconSize: 36,
                  tooltip: hasQuestions ? 'Question' : null,
                  icon: const Icon(Icons.quiz_outlined),
                  onPressed: hasQuestions ? onQuestions : null,
                ),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: pageIndex < pageCount - 1 ? onNext : null,
              ),
            ],
          ),
          if (arAvailable && hasQuestions)
            TextButton.icon(
              onPressed: onQuestions,
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Question'),
            ),
        ],
      ),
    );
  }
}

class _TtsFallbackBanner extends StatelessWidget {
  const _TtsFallbackBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Text(
        'Dev preview voice — final stories use reviewed narration.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
