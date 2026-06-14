import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../shared/widgets/async_views.dart';
import '../player/narration_player.dart';
import '../player/player_providers.dart';
import '../profile/profile_providers.dart';
import 'ar_scene_controller.dart';

/// AR story mode (§7.1.4, §9.3). Renders the page's published `scene_json` as a
/// 2D character over a live camera preview and plays the linked audio segment
/// when the child taps the character (§9.3.3 `play_audio_segment`).
///
/// Tracking mode is resolved by [ArCapabilities]: native ARKit/ARCore
/// image-target anchoring when wired + on-device, else a camera-preview overlay
/// so the full data path runs without hardware/reference images.
class ArStoryScreen extends ConsumerWidget {
  const ArStoryScreen({
    super.key,
    required this.storyId,
    required this.pageId,
  });

  final String storyId;
  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(storyDetailProvider(storyId));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('AR Story'),
      ),
      extendBodyBehindAppBar: true,
      body: detail.when(
        loading: () => const LoadingView(),
        error: (_, _) =>
            const ErrorView(message: "We couldn't start the AR scene."),
        data: (d) {
          final scene = d?.arSceneForPage(pageId);
          final page = d?.orderedPages
              .where((p) => p.id == pageId)
              .firstOrNull;
          if (d == null || scene == null || page == null) {
            return const ErrorView(message: 'No AR scene for this page.');
          }
          return _ArView(detail: d, scene: scene, page: page);
        },
      ),
    );
  }
}

class _ArView extends ConsumerStatefulWidget {
  const _ArView({
    required this.detail,
    required this.scene,
    required this.page,
  });

  final StoryDetail detail;
  final ArScene scene;
  final StoryPage page;

  @override
  ConsumerState<_ArView> createState() => _ArViewState();
}

class _ArViewState extends ConsumerState<_ArView> {
  final NarrationPlayer _audio = NarrationPlayer();
  CameraController? _camera;
  bool _cameraReady = false;
  late final ArTrackingMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = ArCapabilities.resolveMode(widget.page);
    _initCamera();
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
      // No camera (simulator/desktop/denied) → soft background fallback.
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  /// Resolve and play the audio segment bound to a tapped asset (§9.3.3).
  Future<void> _onTapAsset(ArSceneAsset asset) async {
    final interaction = widget.scene.sceneJson.interactions
        .where((i) =>
            i.trigger == ArTrigger.tap && i.targetAssetId == asset.assetId)
        .firstOrNull;
    if (interaction?.action != ArAction.playAudioSegment) return;

    final segment = widget.detail.segments
        .where((s) => s.id == interaction!.audioSegmentId)
        .firstOrNull;
    if (segment == null) return;

    final profile = ref.read(childProfileProvider).value;
    await _audio.load([segment], languageCode: profile?.languageCode ?? 'en');
    await _audio.play();
  }

  @override
  void dispose() {
    _audio.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _background(),
        // Place each scene asset using its normalized position offset.
        for (final asset in widget.scene.sceneJson.assets)
          Align(
            alignment: Alignment(
              asset.position.x.clamp(-1.0, 1.0),
              // Negative y in scene space sits lower on screen.
              (-asset.position.y).clamp(-1.0, 1.0),
            ),
            child: _ArCharacter(
              asset: asset,
              onTap: () => _onTapAsset(asset),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Column(
            children: [
              const Icon(Icons.touch_app_rounded, color: Colors.white70),
              const SizedBox(height: 4),
              Text(
                'Tap the character to hear them speak',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
              if (_mode == ArTrackingMode.cameraPreview)
                Text(
                  'Preview mode',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.white38),
                ),
            ],
          ),
        ),
      ],
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

/// A simple animated 2D character. Renders the asset image when present, else a
/// themed glyph, with a gentle idle bob (§3.7 idle/wave animation set).
class _ArCharacter extends StatefulWidget {
  const _ArCharacter({required this.asset, required this.onTap});

  final ArSceneAsset asset;
  final VoidCallback onTap;

  @override
  State<_ArCharacter> createState() => _ArCharacterState();
}

class _ArCharacterState extends State<_ArCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 160.0 * widget.asset.scale;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -8 * _controller.value),
          child: child,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: _visual(size),
        ),
      ),
    );
  }

  Widget _visual(double size) {
    final asset = widget.asset.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(asset,
          errorBuilder: (_, _, _) => _glyph(size));
    }
    return _glyph(size);
  }

  Widget _glyph(double size) {
    final emoji = switch (widget.asset.type) {
      ArAssetType.object2d => '⭐',
      _ => _characterEmoji(widget.asset.assetId),
    };
    return Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.7)));
  }

  static String _characterEmoji(String assetId) {
    final id = assetId.toLowerCase();
    if (id.contains('owl')) return '🦉';
    if (id.contains('bunny')) return '🐰';
    if (id.contains('bear')) return '🐻';
    if (id.contains('star')) return '⭐';
    if (id.contains('fox')) return '🦊';
    return '🐾';
  }
}
