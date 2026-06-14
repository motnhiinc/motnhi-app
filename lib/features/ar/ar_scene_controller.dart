import 'dart:io' show Platform;

import '../../data/models/models.dart';

/// How an AR scene is anchored to the world.
enum ArTrackingMode {
  /// Native ARKit/ARCore augmented-image tracking, anchored to the printed
  /// page (§9.3, §3.3). Requires a device + a registered reference image.
  imageTarget,

  /// Camera-preview overlay with no world anchoring — always available, used
  /// on simulators/desktop or when no reference image is registered. Exercises
  /// the full `scene_json` → asset → tap-audio path (§3.6).
  cameraPreview,
}

/// Capability gate for AR. Real image-target tracking will use a native
/// ARKit (iOS) / ARCore (Android) plugin, which needs native configuration, a
/// physical device, and printed reference images. That native AR package is
/// not a dependency yet — it lands in the dedicated "wire native AR" slice.
/// Until then, [resolveMode] selects the camera-preview realization so the
/// experience runs everywhere.
abstract final class ArCapabilities {
  /// Flip to true once a native ARKit/ARCore image-anchor plugin is added and
  /// validated on-device (the remaining hardware follow-up).
  static const bool nativeImageTrackingWired = false;

  static bool get _isMobile {
    try {
      return Platform.isIOS || Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static ArTrackingMode resolveMode(StoryPage page) {
    if (nativeImageTrackingWired && _isMobile && page.hasImageTarget) {
      return ArTrackingMode.imageTarget;
    }
    return ArTrackingMode.cameraPreview;
  }
}
