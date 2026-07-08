import '../../data/models/image_target_manifest.dart';
import '../../data/models/models.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sources/image_target_resolver.dart';
import 'page_detector.dart';

/// Orchestrates the scan-to-read flow (§5.3, §6): fetch manifest → build the
/// detector → on a manifest-page detection start a single `scan` session, play
/// the page's narration (via the injected [onPlayPage] callback), then record a
/// `scan_success` event.
///
/// A plain, unit-testable class (not a widget): every dependency is injected so
/// tests can drive it. Narration lives behind [onPlayPage] so the screen binds
/// it to the existing `NarrationPlayer` while orchestration stays testable.
class ScanFlowController {
  ScanFlowController({
    required ImageTargetResolver resolver,
    required SessionRepository sessionRepository,
    required PageDetector Function(ImageTargetManifest) detectorFactory,
    required String childProfileId,
    required String storyId,
    required Future<void> Function(String pageId) onPlayPage,
  })  : _resolver = resolver,
        _sessionRepository = sessionRepository,
        _detectorFactory = detectorFactory,
        _childProfileId = childProfileId,
        _storyId = storyId,
        _onPlayPage = onPlayPage;

  final ImageTargetResolver _resolver;
  final SessionRepository _sessionRepository;
  final PageDetector Function(ImageTargetManifest) _detectorFactory;
  final String _childProfileId;
  final String _storyId;
  final Future<void> Function(String pageId) _onPlayPage;

  ImageTargetManifest? _manifest;
  PageDetector? _detector;

  /// Guards single-session creation: the first detection starts the session and
  /// every later detection reuses it (§5.3 "create session on first detection").
  Future<StorySession>? _sessionFuture;

  /// The fetched manifest, exposed so a panel can render its pages.
  ImageTargetManifest? get manifest => _manifest;

  /// The built detector (a [SimulatedPageDetector] while native tracking is
  /// unwired), exposed so the screen can wire the simulated page panel to it.
  PageDetector? get detector => _detector;

  /// Fetches the manifest, builds the detector via the injected factory, and
  /// registers the detection handler (§5.3 step 1).
  Future<void> start() async {
    final manifest = await _resolver.fetch(_storyId);
    _manifest = manifest;
    final detector = _detectorFactory(manifest);
    detector.onDetected = handleDetected;
    _detector = detector;
  }

  /// Handles a detected `page_id` (§5.3 step 3). No-op when the page is not in
  /// the manifest. Otherwise starts the scan session once, plays the page, then
  /// records a `scan_success` event.
  ///
  /// Registered as the detector's `void` callback; returns a [Future] so tests
  /// can await the full chain (the seam discards it in production).
  Future<void> handleDetected(String pageId) async {
    final manifest = _manifest;
    if (manifest == null) return;
    if (!manifest.targets.any((t) => t.pageId == pageId)) return;

    final session = await _ensureSession();
    await _onPlayPage(pageId);
    await _sessionRepository.recordEvent(
      sessionId: session.id,
      eventType: 'scan_success',
      pageId: pageId,
    );
  }

  Future<StorySession> _ensureSession() => _sessionFuture ??=
      _sessionRepository.startSession(
        childProfileId: _childProfileId,
        storyId: _storyId,
        mode: SessionMode.scan,
      );
}
