import '../../data/models/image_target_manifest.dart';
import 'page_detector.dart';

/// Manifest-driven stand-in for native image tracking (§5.2). Built from a
/// manifest's `targets`; the scan screen renders a dev panel of pages and a tap
/// emits that page's `page_id` through the same [onDetected] seam the native
/// detector will use. Gated behind `ArCapabilities.nativeImageTrackingWired`.
class SimulatedPageDetector implements PageDetector {
  SimulatedPageDetector(this._targets)
      : _pageIds = _targets.map((t) => t.pageId).toList(growable: false);

  /// Builds a detector from a fetched manifest's targets.
  factory SimulatedPageDetector.fromManifest(ImageTargetManifest manifest) =>
      SimulatedPageDetector(manifest.targets);

  final List<ImageTarget> _targets;
  final List<String> _pageIds;

  @override
  PageDetectedCallback? onDetected;

  /// The manifest targets, exposed so a UI panel can render a page per target.
  List<ImageTarget> get targets => List.unmodifiable(_targets);

  /// The manifest page ids, for the dev panel and no-op validation.
  List<String> get pageIds => List.unmodifiable(_pageIds);

  /// Emits [pageId] through [onDetected] only if it is one of the manifest
  /// page ids; an unknown page is a no-op (§7 "not in manifest → ignore").
  void simulateDetection(String pageId) {
    if (!_pageIds.contains(pageId)) return;
    onDetected?.call(pageId);
  }
}
