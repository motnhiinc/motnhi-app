import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../player/narration_player.dart';
import '../player/player_providers.dart';
import '../profile/profile_providers.dart';
import 'ar_scene_controller.dart';
import 'scan_flow_controller.dart';
import 'simulated_page_detector.dart';
import 'simulated_page_panel.dart';

/// Book-first scan-to-read mode. Native page recognition is still unwired, so
/// this hosts the scan flow against a simulated page panel over camera preview.
class ScanStoryScreen extends ConsumerWidget {
  const ScanStoryScreen({super.key, required this.storyId});

  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(childProfileProvider);
    final detail = ref.watch(storyDetailProvider(storyId));

    if (profile.isLoading || detail.isLoading) {
      return const Scaffold(
        body: LoadingView(message: 'Starting scan...'),
      );
    }
    if (profile.hasError ||
        detail.hasError ||
        profile.value == null ||
        detail.value == null) {
      return const Scaffold(
        body: ErrorView(message: "We couldn't start scanning."),
      );
    }

    return _ScanView(
      storyId: storyId,
      detail: detail.value!,
      childProfile: profile.value!,
    );
  }
}

class _ScanView extends ConsumerStatefulWidget {
  const _ScanView({
    required this.storyId,
    required this.detail,
    required this.childProfile,
  });

  final String storyId;
  final StoryDetail detail;
  final ChildProfile childProfile;

  @override
  ConsumerState<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends ConsumerState<_ScanView> {
  late final NarrationPlayer _audio;
  late final ScanFlowController _controller;
  CameraController? _camera;
  bool _cameraReady = false;
  bool _starting = true;
  bool _error = false;
  int? _playingPageNumber;

  /// Guards against interleaved `NarrationPlayer.load` calls: a tap arriving
  /// while a load is in flight is ignored (kids mash the page list).
  bool _loading = false;

  /// Bumped per accepted tap so a finished page's completion handler only
  /// clears the banner when it is still the current page.
  int _playGen = 0;

  @override
  void initState() {
    super.initState();
    _audio = NarrationPlayer(resolver: ref.read(assetUrlResolverProvider));
    _controller = ScanFlowController(
      resolver: ref.read(imageTargetResolverProvider),
      sessionRepository: ref.read(sessionRepositoryProvider),
      detectorFactory: ref.read(pageDetectorProvider),
      childProfileId: widget.childProfile.id,
      storyId: widget.storyId,
      onPlayPage: _playPage,
    );
    unawaited(_initCamera());
    unawaited(_startScanning());
  }

  Future<void> _startScanning() async {
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  Future<void> _playPage(String pageId) async {
    if (!mounted || _loading) return;
    final segments = widget.detail.segmentsForPage(pageId);
    if (segments.isEmpty) return;
    final gen = ++_playGen;
    final pageNumber = _controller.manifest?.targets
        .firstWhere((target) => target.pageId == pageId)
        .pageNumber;
    setState(() => _playingPageNumber = pageNumber);
    _loading = true;
    try {
      await _audio.load(
        segments,
        languageCode: widget.childProfile.languageCode,
      );
    } finally {
      _loading = false;
    }
    if (!mounted) return;
    unawaited(_audio.play().whenComplete(() {
      // Only clear the banner if this page is still the current one; a newer
      // tap (higher generation) owns the banner otherwise.
      if (mounted && gen == _playGen) {
        setState(() => _playingPageNumber = null);
      }
    }));
  }

  @override
  void dispose() {
    unawaited(_audio.dispose());
    unawaited(_camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan (Preview)'),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _background(),
          SafeArea(child: _bodyState()),
          if (_playingPageNumber != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _NowPlayingBanner(pageNumber: _playingPageNumber!),
            ),
        ],
      ),
    );
  }

  Widget _bodyState() {
    if (_error) {
      return const ErrorView(message: "We couldn't start scanning.");
    }
    if (_starting) {
      return const LoadingView(message: 'Starting scan...');
    }

    final detector = _controller.detector;
    if (detector == null) {
      return const ErrorView(message: "We couldn't start scanning.");
    }
    assert(
      !ArCapabilities.nativeImageTrackingWired,
      'Replace the simulated page panel once native tracking is wired.',
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: SimulatedPagePanel(
            detector: detector as SimulatedPageDetector,
          ),
        ),
      ),
    );
  }

  Widget _background() {
    if (_cameraReady && _camera != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _camera!.value.previewSize?.height ?? 1080,
          height: _camera!.value.previewSize?.width ?? 1920,
          child: CameraPreview(_camera!),
        ),
      );
    }
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243B55), Color(0xFF141E30)],
        ),
      ),
    );
  }
}

class _NowPlayingBanner extends StatelessWidget {
  const _NowPlayingBanner({required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'Playing page $pageNumber...',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
