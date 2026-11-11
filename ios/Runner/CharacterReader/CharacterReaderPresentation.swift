import Foundation
import simd

enum CharacterPlacementState: Equatable {
  case searching, placed, moving

  var isPreviewing: Bool { self != .placed }
  var hasPlacement: Bool { self != .searching }

  mutating func beginMove() {
    if self == .placed { self = .moving }
  }

  mutating func cancelMove() {
    if self == .moving { self = .placed }
  }

  mutating func confirm() { self = .placed }
}

enum CharacterPlacementEligibility: Equatable {
  case searching, provisional, ready

  static func evaluate(normalTracking: Bool, hasHit: Bool, trackedPlane: Bool,
                       upwardNormal: Float) -> Self {
    guard normalTracking, hasHit, upwardNormal.isFinite, upwardNormal > 0.9 else {
      return .searching
    }
    return trackedPlane ? .ready : .provisional
  }
}

/// A stable measured surface, not a timer over an estimated plane. Position is
/// compared with the start of the dwell so slow drift cannot accumulate.
struct CharacterSurfaceDwell {
  private var planeId: UUID?
  private var origin = SIMD3<Float>(repeating: 0)
  private var started: TimeInterval?
  private var last: TimeInterval?
  private var samples = 0

  mutating func reset() { planeId = nil; started = nil; last = nil; samples = 0 }

  mutating func update(plane: UUID?, position: SIMD3<Float>, at time: TimeInterval) -> Bool {
    guard let plane, time.isFinite, (0..<3).allSatisfy({ position[$0].isFinite }) else {
      reset(); return false
    }
    // Display refresh can outpace the camera. One camera frame is only one sample.
    if planeId == plane, time == last { return samples >= 10 && time - (started ?? time) >= 0.8 }
    if planeId != plane || simd_distance(origin, position) > 0.035 || started == nil ||
       time - (last ?? time) > 0.2 || time < (last ?? time) {
      planeId = plane; origin = position; started = time
      samples = 0
    }
    last = time
    samples += 1
    return samples >= 10 && time - (started ?? time) >= 0.8
  }
}

/// Conservative disk containment in ARKit's convex measured boundary, not its
/// rectangular extent (which can include unobserved space at table corners).
enum CharacterSurfaceGeometry {
  static func footprintRadius(extents: SIMD3<Float>) -> Float? {
    guard (0..<3).allSatisfy({ extents[$0].isFinite && extents[$0] >= 0 }),
          let largest = [extents.x, extents.y, extents.z].max(), largest > 0 else { return nil }
    let half = extents / largest * 0.175
    return simd_length(SIMD2(half.x, half.z)) + 0.01
  }

  static func containsFootprint(center: SIMD2<Float>, radius: Float,
                                boundary: [SIMD2<Float>]) -> Bool {
    guard center.x.isFinite, center.y.isFinite, radius.isFinite, radius > 0,
          boundary.count >= 3 else { return false }
    var winding: Float = 0
    for index in boundary.indices {
      let a = boundary[index], b = boundary[(index + 1) % boundary.count]
      guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return false }
      let edge = b - a
      let length = simd_length(edge)
      guard length > 0.00001 else { return false }
      let offset = center - a
      let cross = edge.x * offset.y - edge.y * offset.x
      guard abs(cross) / length >= radius else { return false }
      if winding == 0 { winding = cross }
      else if winding * cross <= 0 { return false }
    }
    return true
  }

  static func reachable(position: SIMD3<Float>, camera: SIMD3<Float>) -> Bool {
    let distance = simd_distance(position, camera)
    return distance.isFinite && distance >= 0.25 && distance <= 3 &&
      (camera.y - position.y) / distance >= 0.25
  }
}

/// Require parallax and a stable surface height, independently of reticle dwell.
struct CharacterSurfaceVerification {
  private var planeId: UUID?
  private var height: Float = 0
  private var cameraOrigin = SIMD2<Float>(repeating: 0)
  private var started: TimeInterval = 0
  private var last: TimeInterval = 0
  private var hasBaseline = false

  mutating func reset() { planeId = nil; hasBaseline = false }

  mutating func update(plane: UUID?, height: Float, camera: SIMD2<Float>,
                       at time: TimeInterval) -> Bool {
    guard let plane, height.isFinite, camera.x.isFinite, camera.y.isFinite, time.isFinite else {
      reset(); return false
    }
    if planeId != plane || time < last || time - last > 0.2 || abs(height - self.height) > 0.02 {
      planeId = plane; self.height = height; cameraOrigin = camera
      started = time; hasBaseline = false
    }
    last = time
    hasBaseline = hasBaseline || simd_distance(camera, cameraOrigin) >= 0.08
    return hasBaseline && time - started >= 1.5
  }
}

/// Debounces both loss and recovery, without ever requesting automatic playback resumption.
struct CharacterTrackingRecovery {
  private var lossStarted: TimeInterval?
  private var recoveryStarted: TimeInterval?
  private(set) var requiresRecovery = false

  mutating func update(healthy: Bool, at time: TimeInterval) -> Bool {
    if healthy {
      lossStarted = nil
      if requiresRecovery {
        if recoveryStarted == nil { recoveryStarted = time }
        if time - (recoveryStarted ?? time) >= 0.5 { requiresRecovery = false }
      }
    } else {
      recoveryStarted = nil
      if lossStarted == nil { lossStarted = time }
      if time - (lossStarted ?? time) >= 1 { requiresRecovery = true }
    }
    return requiresRecovery
  }
}

enum CharacterPresentationState: Equatable {
  case idle, speaking, paused

  static func resolve(playback: CharacterReaderPlaybackState, audioIsPlaying: Bool) -> Self {
    if playback == .playing && audioIsPlaying { return .speaking }
    return playback == .paused ? .paused : .idle
  }
}

enum CharacterAssetPresentation {
  /// Entity.load enumeration, macOS AND iOS 27.0 simulator, Xcode 27.1 (27A9275),
  /// 2026-10-22: all seven loaded roots (empty name) expose this aggregate resource. It includes the
  /// single baked Idle-like SkelAnim AND its bone-node tracks, unlike a child alias.
  /// iOS must independently match the exact owner/name/duration or use a stable pose.
  /// Loop seams, skinned foot contact and visual quality remain device-UNVERIFIED.
  static func clipName(asset: String, state: CharacterPresentationState) -> String? {
    guard idleDuration(asset: asset) != nil else { return nil }
    return "global scene animation" // Speaking deliberately retains idle, not a talking clip.
  }

  static func idleDuration(asset: String) -> TimeInterval? {
    if asset == "scan_any_page_character" { return 3.3333332538604736 }
    if ["cute_doll_v01", "cute_doll_v02", "cute_doll_v03", "cute_doll_v04",
        "cute_doll_v05", "cute_doll_v06"].contains(asset) { return 16.633333206176758 }
    return nil
  }

  static func validatesIdle(asset: String, ownerPath: [String], name: String?,
                            duration: TimeInterval) -> Bool {
    guard let expected = idleDuration(asset: asset) else { return false }
    return ownerPath == [""] && name == clipName(asset: asset, state: .idle) &&
      duration.isFinite && abs(duration - expected) < 0.01
  }
  static func auditedForwardAxisOffset(asset: String) -> Float? { nil }

  /// Orients a +Z presentation basis toward the viewer. Actual mesh facing remains unverified
  /// until an audited per-asset correction is supplied above.
  static func viewerYaw(position: SIMD3<Float>, camera: SIMD3<Float>) -> Float {
    let delta = camera - position
    guard delta.x.isFinite, delta.z.isFinite,
          delta.x * delta.x + delta.z * delta.z > 0.0001 else { return 0 }
    return atan2(delta.x, delta.z)
  }
}

/// Persistent reader adjustment, independent of placement anchors, authored transforms,
/// story pages and playback. Move/Cancel do not change it. Reset affects only size/yaw;
/// yaw zero means the viewer-facing basis captured at the latest confirmed placement.
struct CharacterAdjustment: Equatable {
  // Conservative bounds relative to the 35 cm largest-dimension normalization, NOT height.
  // Physical-device size/gesture tuning remains UNVERIFIED.
  static let scaleRange: ClosedRange<Float> = 0.5...1.5
  private(set) var scale: Float = 1
  private(set) var yaw: Float = 0

  mutating func setScale(_ value: Float) {
    guard value.isFinite else { return }
    scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, value))
  }

  mutating func setYaw(_ value: Float) {
    guard value.isFinite else { return }
    yaw = atan2(sin(value), cos(value))
  }

  mutating func reset() { self = Self() }

  static func canAdjust(placement: CharacterPlacementState, healthy: Bool,
                        recovering: Bool, active: Bool, terminal: Bool) -> Bool {
    placement == .placed && healthy && !recovering && active && !terminal
  }
}

/// A one-time static-bounds normalization nested INSIDE the adjustment pivot. Rotating
/// the adjustment never rotates the centering offset around the asset's authored origin.
/// This keeps the bottom-center reference fixed; it does not promise animated planted feet.
struct CharacterModelNormalization {
  let scale: Float
  let translation: SIMD3<Float>

  init?(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
    guard (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite &&
      maximum[$0] >= minimum[$0] }) else { return nil }
    let extents = maximum - minimum
    let largest = max(extents.x, extents.y, extents.z)
    guard largest > 0 else { return nil }
    let uniformScale = 0.35 / largest
    let center = minimum / 2 + maximum / 2
    let offset = -SIMD3(center.x, minimum.y, center.z) * uniformScale
    guard uniformScale.isFinite, uniformScale > 0,
          (0..<3).allSatisfy({ offset[$0].isFinite }) else { return nil }
    scale = uniformScale
    translation = offset
  }
}

enum CharacterAnimationPolicy {
  static func shouldPlay(state: CharacterPresentationState, placement: CharacterPlacementState,
                         active: Bool, interrupted: Bool, failed: Bool, recovering: Bool) -> Bool {
    state != .paused && placement == .placed && active && !interrupted && !failed && !recovering
  }
}

struct CharacterExperimentalCapability: Equatable {
  let apiAvailable: Bool
  let supported: Bool
  let requested: Bool
  var configured: Bool { apiAvailable && supported && requested }
}

/// Completion belongs to a successfully started player cycle, not to the UI's current
/// Play/Pause state. Pausing does not invalidate a pending completion. Replacing the
/// player, retrying after failure, or consuming its completion does. A queued callback
/// carries the cycle it observed so it cannot consume a later explicit replay.
struct CharacterAudioCompletionPolicy {
  enum Outcome: Equatable { case ignored, failed, completed }
  private(set) var cycle: UInt = 0
  private var awaitingCompletion = false

  mutating func started() {
    guard !awaitingCompletion else { return } // Resume belongs to the same clip cycle.
    cycle &+= 1
    awaitingCompletion = true
  }

  mutating func invalidate() {
    cycle &+= 1
    awaitingCompletion = false
  }

  mutating func consume(cycle: UInt, successfully: Bool) -> Outcome {
    guard cycle == self.cycle, awaitingCompletion else { return .ignored }
    awaitingCompletion = false
    return successfully ? .completed : .failed
  }

  static func canAutostart(playback: CharacterReaderPlaybackState,
                           placement: CharacterPlacementState, active: Bool,
                           healthy: Bool, recovering: Bool) -> Bool {
    playback == .playing && placement == .placed && active && healthy && !recovering
  }
}

func readerText(_ key: String) -> String {
  NSLocalizedString(key, tableName: "CharacterReader", bundle: .main, comment: "AR reader")
}
