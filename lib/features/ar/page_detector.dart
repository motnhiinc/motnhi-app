/// Invoked when the detector recognizes a page, carrying its `page_id`
/// (§5.2). Synchronous by design so the seam stays trivially unit-testable.
typedef PageDetectedCallback = void Function(String pageId);

/// A stable seam that emits a recognized `page_id` (§5.2). The scan flow
/// registers [onDetected]; the simulated implementation fires it on a dev-panel
/// tap and a future native ARKit/ARCore detector fires the same callback when a
/// reference image is matched.
abstract class PageDetector {
  /// Registered by the scan flow; called with the recognized `page_id`.
  PageDetectedCallback? onDetected;
}
