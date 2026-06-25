import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../core/router/app_router.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../../shared/widgets/big_play_button.dart';
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
  final PageController _pageController = PageController();
  int _pageIndex = 0;
  String? _sessionId;
  bool _storyCompleted = false;

  List<StoryPage> get _pages => widget.detail.orderedPages;
  Story get _story => widget.detail.story;

  @override
  void initState() {
    super.initState();
    _player = NarrationPlayer(resolver: ref.read(assetUrlResolverProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
      _loadPage(0, autoplay: false);
      _player.isComplete.addListener(_onMaybeComplete);
    });
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

  Future<void> _loadPage(int index, {required bool autoplay}) async {
    final page = _pages[index];
    await _player.load(
      widget.detail.segmentsForPage(page.id),
      speedMultiplier: _effectiveSpeed(),
      languageCode: _story.languageCode,
    );
    final sid = _sessionId;
    if (sid != null) {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.updateLastPage(sid, page.pageNumber);
      await repo.recordEvent(
        sessionId: sid,
        eventType: 'page_viewed',
        pageId: page.id,
        payload: {'page_number': page.pageNumber},
      );
    }
    if (autoplay) await _player.play();
  }

  void _onPageChanged(int index) {
    setState(() => _pageIndex = index);
    _loadPage(index, autoplay: true);
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
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
    final arScene = widget.detail.arSceneForPage(page.id);
    final profile = ref.watch(childProfileProvider).value;
    final arAvailable = arScene != null && (profile?.arEnabled ?? true);
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
              onAr: () async {
                await _player.pause();
                if (context.mounted) {
                  context.push(AppRoutes.ar(_story.id, page.id));
                }
              },
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
                valueListenable: player.isPlaying,
                builder: (_, playing, _) => BigPlayButton(
                  isPlaying: playing,
                  onPressed: () =>
                      playing ? player.pause() : player.play(),
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
