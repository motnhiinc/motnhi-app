import UIKit
import XCTest
import simd
@testable import Runner

final class CharacterReaderPresentationTests: XCTestCase {
  func testAutomaticPlacementRequiresContinuousStableMeasuredSurface() {
    var dwell = CharacterSurfaceDwell()
    let plane = UUID()
    let position = SIMD3<Float>(0, 0, -1)
    for frame in 0..<16 {
      XCTAssertFalse(dwell.update(plane: plane, position: position, at: Double(frame) * 0.05))
    }
    XCTAssertTrue(dwell.update(plane: plane, position: position, at: 0.85))
    XCTAssertFalse(dwell.update(plane: nil, position: position, at: 0.9))
    XCTAssertFalse(dwell.update(plane: plane, position: position, at: 1))
    XCTAssertFalse(dwell.update(plane: plane, position: position, at: 2)) // Missing frames.
    XCTAssertFalse(dwell.update(plane: UUID(), position: position, at: 2.05))
  }

  func testAutomaticPlacementRejectsAccumulatedSlowDrift() {
    var dwell = CharacterSurfaceDwell()
    let plane = UUID()
    for frame in 0..<50 {
      XCTAssertFalse(dwell.update(plane: plane, position: SIMD3(Float(frame) * 0.005, 0, -1),
        at: Double(frame) * 0.05))
    }
  }
  func testQueuedSuccessfulCompletionSurvivesPauseMoveAndInactivityWithoutAutostart() {
    for interruption in ["pause", "move", "inactive"] {
      var completion = CharacterAudioCompletionPolicy()
      var playback = CharacterReaderPlaybackState.playing
      var placement = CharacterPlacementState.placed
      var active = true
      var clipIndex = 0
      completion.started()
      let queuedCycle = completion.cycle // Genuine completion arrives before interruption.

      _ = playback.pauseForInterruption()
      if interruption == "move" { placement.beginMove() }
      if interruption == "inactive" { active = false }

      // The queued handler consumes success despite the changed UI/lifecycle state.
      XCTAssertEqual(completion.consume(cycle: queuedCycle, successfully: true), .completed)
      XCTAssertFalse(CharacterAudioCompletionPolicy.canAutostart(playback: playback,
        placement: placement, active: active, healthy: true, recovering: false))
      clipIndex += 1 // Preload the NEXT clip, as the reader's successful-completion handler does.
      completion.invalidate()
      XCTAssertEqual(playback, .paused)
      XCTAssertEqual(clipIndex, 1)
      XCTAssertEqual(completion.consume(cycle: queuedCycle, successfully: true), .ignored)

      // Move/foreground recovery alone never starts audio. Explicit Resume starts clip 1,
      // not the completed clip 0, and an old queued callback cannot consume this new cycle.
      placement.cancelMove()
      active = true
      XCTAssertFalse(CharacterAudioCompletionPolicy.canAutostart(playback: playback,
        placement: placement, active: active, healthy: true, recovering: false))
      completion.started()
      playback = .playing
      XCTAssertEqual(clipIndex, 1)
      XCTAssertNotEqual(completion.cycle, queuedCycle)
      XCTAssertEqual(completion.consume(cycle: queuedCycle, successfully: true), .ignored)
      XCTAssertEqual(completion.consume(cycle: completion.cycle, successfully: true), .completed)
    }
  }

  func testPageEndCompletionIsConsumedOnceAndExplicitReplayGetsANewCycle() {
    var completion = CharacterAudioCompletionPolicy()
    completion.started()
    let queuedCycle = completion.cycle
    var playback = CharacterReaderPlaybackState.playing
    _ = playback.pauseForInterruption()
    var pageEndResets = 0
    for _ in 0..<2 {
      if completion.consume(cycle: queuedCycle, successfully: true) == .completed {
        pageEndResets += 1
        playback = .ready // The page-end handler displays finished status, not Resume.
      }
    }
    XCTAssertEqual(pageEndResets, 1)
    XCTAssertEqual(playback, .ready)
    completion.started() // Explicit Read again.
    XCTAssertNotEqual(completion.cycle, queuedCycle)
    XCTAssertEqual(completion.consume(cycle: queuedCycle, successfully: true), .ignored)
  }

  func testUnstartedFailedAndReplacedCyclesNeverBecomeSuccessfulCompletion() {
    var completion = CharacterAudioCompletionPolicy()
    XCTAssertEqual(completion.consume(cycle: completion.cycle, successfully: true), .ignored)
    completion.started()
    let failedCycle = completion.cycle
    XCTAssertEqual(completion.consume(cycle: failedCycle, successfully: false), .failed)
    XCTAssertEqual(completion.consume(cycle: failedCycle, successfully: true), .ignored)
    completion.started()
    let replacedCycle = completion.cycle
    completion.invalidate() // Player replacement or decode failure/retry.
    completion.started()
    XCTAssertEqual(completion.consume(cycle: replacedCycle, successfully: true), .ignored)
    XCTAssertEqual(completion.consume(cycle: completion.cycle, successfully: true), .completed)
  }

  func testResumeKeepsPendingCompletionCycleButAutostartRequiresAllPlaybackGates() {
    var completion = CharacterAudioCompletionPolicy()
    completion.started()
    let cycle = completion.cycle
    completion.started() // Resuming a paused, unfinished player is not a new clip.
    XCTAssertEqual(completion.cycle, cycle)
    for playback in [CharacterReaderPlaybackState.ready, .playing, .paused, .retry] {
      for placement in [CharacterPlacementState.searching, .placed, .moving] {
        for active in [false, true] {
          for healthy in [false, true] {
            for recovering in [false, true] {
              XCTAssertEqual(CharacterAudioCompletionPolicy.canAutostart(playback: playback,
                placement: placement, active: active, healthy: healthy, recovering: recovering),
                playback == .playing && placement == .placed && active && healthy && !recovering)
            }
          }
        }
      }
    }
  }

  func testOnlyNormalTrackingAndUpwardTrackedSurfaceIsReady() {
    XCTAssertEqual(eligibility(normal: true, tracked: true, up: 1), .ready)
    XCTAssertEqual(eligibility(normal: true, tracked: false, up: 1), .provisional)
    XCTAssertEqual(eligibility(normal: false, tracked: true, up: 1), .searching)
    XCTAssertEqual(eligibility(normal: true, tracked: true, up: -1), .searching)
    XCTAssertEqual(eligibility(normal: true, tracked: true, up: 0.5), .searching)
    XCTAssertEqual(eligibility(normal: true, tracked: true, up: .nan), .searching)
    XCTAssertEqual(CharacterPlacementEligibility.evaluate(normalTracking: true,
      hasHit: false, trackedPlane: true, upwardNormal: 1), .searching)
  }

  func testMoveCancelRetainsCommittedPlacementAndConfirmationReplacesIt() {
    var placement = CharacterPlacementState.searching
    placement.beginMove()
    XCTAssertEqual(placement, .searching)
    placement.confirm()
    for _ in 0..<20 {
      placement.beginMove()
      XCTAssertEqual(placement, .moving)
      XCTAssertTrue(placement.hasPlacement)
      XCTAssertTrue(placement.isPreviewing)
      placement.cancelMove()
      XCTAssertEqual(placement, .placed)
      placement.beginMove()
      placement.confirm()
      XCTAssertEqual(placement, .placed)
      XCTAssertFalse(placement.isPreviewing)
    }
  }

  func testBriefTrackingLossDoesNotPauseButSustainedLossDoes() {
    var recovery = CharacterTrackingRecovery()
    XCTAssertFalse(recovery.update(healthy: false, at: 0))
    XCTAssertFalse(recovery.update(healthy: false, at: 0.9))
    XCTAssertFalse(recovery.update(healthy: true, at: 0.95))
    XCTAssertFalse(recovery.update(healthy: false, at: 1))
    XCTAssertTrue(recovery.update(healthy: false, at: 2.01))
    XCTAssertTrue(recovery.update(healthy: true, at: 2.1))
    XCTAssertFalse(recovery.update(healthy: true, at: 2.61))
  }

  func testRecoveryMustBeContinuouslyHealthyAndNeverResumesPlayback() {
    var recovery = CharacterTrackingRecovery()
    var playback = CharacterReaderPlaybackState.playing
    _ = recovery.update(healthy: false, at: 0)
    if recovery.update(healthy: false, at: 1.1) { _ = playback.pauseForInterruption() }
    XCTAssertEqual(playback, .paused)
    XCTAssertTrue(recovery.update(healthy: true, at: 2))
    XCTAssertTrue(recovery.update(healthy: false, at: 2.4))
    XCTAssertTrue(recovery.update(healthy: true, at: 3))
    XCTAssertTrue(recovery.update(healthy: true, at: 3.4))
    XCTAssertFalse(recovery.update(healthy: true, at: 3.6))
    XCTAssertEqual(playback, .paused)
  }

  func testSpeakingRequiresSuccessfulPlaybackAndPauseStopsSpeaking() {
    XCTAssertEqual(CharacterPresentationState.resolve(playback: .playing, audioIsPlaying: false), .idle)
    XCTAssertEqual(CharacterPresentationState.resolve(playback: .playing, audioIsPlaying: true), .speaking)
    XCTAssertEqual(CharacterPresentationState.resolve(playback: .paused, audioIsPlaying: false), .paused)
    XCTAssertEqual(CharacterPresentationState.resolve(playback: .retry, audioIsPlaying: false), .idle)
    XCTAssertEqual(CharacterPresentationState.resolve(playback: .ready, audioIsPlaying: false), .idle)
  }

  func testOnlyExactEnumeratedRootIdleContractIsAccepted() {
    for asset in ["scan_any_page_character", "cute_doll_v01", "cute_doll_v02",
                  "cute_doll_v03", "cute_doll_v04", "cute_doll_v05", "cute_doll_v06"] {
      for state in [CharacterPresentationState.idle, .speaking, .paused] {
        XCTAssertEqual(CharacterAssetPresentation.clipName(asset: asset, state: state), "global scene animation")
      }
      let duration = CharacterAssetPresentation.idleDuration(asset: asset)!
      XCTAssertTrue(CharacterAssetPresentation.validatesIdle(asset: asset, ownerPath: [""],
        name: "global scene animation", duration: duration))
      for owner in [[asset], ["", asset], ["", asset, "DollBody", "skeleton__0_SkelRoot"]] {
        XCTAssertFalse(CharacterAssetPresentation.validatesIdle(asset: asset, ownerPath: owner,
          name: "global scene animation", duration: duration))
      }
      for name in ["Idle", "Happy", "default subtree animation", "SkelAnim", ""] {
        XCTAssertFalse(CharacterAssetPresentation.validatesIdle(asset: asset, ownerPath: [""],
          name: name, duration: duration))
      }
      for invalidDuration in [Double.nan, .infinity, 0, duration + 1] {
        XCTAssertFalse(CharacterAssetPresentation.validatesIdle(asset: asset, ownerPath: [""],
          name: "global scene animation", duration: invalidDuration))
      }
      XCTAssertNil(CharacterAssetPresentation.auditedForwardAxisOffset(asset: asset))
    }
    XCTAssertNil(CharacterAssetPresentation.clipName(asset: "unknown", state: .speaking))
    XCTAssertFalse(CharacterAssetPresentation.validatesIdle(asset: "unknown", ownerPath: [""],
      name: "global scene animation", duration: 16.633333))
  }

  func testAdjustmentBoundsRejectNonfiniteAndWrapOnlyYaw() {
    var adjustment = CharacterAdjustment()
    XCTAssertEqual(adjustment.scale, 1)
    adjustment.setScale(100)
    XCTAssertEqual(adjustment.scale, 1.5)
    adjustment.setScale(adjustment.scale * 0.9) // Immediate reversal from a clamped pinch.
    XCTAssertEqual(adjustment.scale, 1.35, accuracy: 0.0001)
    adjustment.setScale(-100)
    XCTAssertEqual(adjustment.scale, 0.5)
    adjustment.setScale(.nan)
    adjustment.setScale(.infinity)
    XCTAssertEqual(adjustment.scale, 0.5)
    adjustment.setYaw(5 * .pi / 2)
    XCTAssertEqual(adjustment.yaw, .pi / 2, accuracy: 0.0001)
    adjustment.setYaw(.nan)
    adjustment.setYaw(.infinity)
    XCTAssertEqual(adjustment.yaw, .pi / 2, accuracy: 0.0001)
  }

  func testAdjustmentPersistsAcrossMoveCancelConfirmAndResetDoesNotTouchStoryOrPlacement() {
    var placement = CharacterPlacementState.placed
    var adjustment = CharacterAdjustment()
    adjustment.setScale(1.3)
    adjustment.setYaw(0.75)
    let retained = adjustment
    var playback = CharacterReaderPlaybackState.playing
    for _ in 0..<20 {
      placement.beginMove()
      _ = playback.pauseForInterruption()
      XCTAssertEqual(adjustment, retained)
      placement.cancelMove()
      XCTAssertEqual(adjustment, retained)
      placement.beginMove()
      placement.confirm()
      XCTAssertEqual(adjustment, retained)
      XCTAssertEqual(playback, .paused)
    }
    adjustment.reset()
    XCTAssertEqual(adjustment, CharacterAdjustment())
    XCTAssertEqual(placement, .placed)
    XCTAssertEqual(playback, .paused)
  }

  func testAdjustmentRequiresHealthyCommittedPlacementAndNeverWorksInPreview() {
    for placement in [CharacterPlacementState.searching, .moving, .placed] {
      for healthy in [false, true] {
        for recovering in [false, true] {
          for active in [false, true] {
            for terminal in [false, true] {
              XCTAssertEqual(CharacterAdjustment.canAdjust(placement: placement, healthy: healthy,
                recovering: recovering, active: active, terminal: terminal),
                placement == .placed && healthy && !recovering && active && !terminal)
            }
          }
        }
      }
    }
  }

  func testNestedNormalizationKeepsBottomCenterAtPivotAcrossSizeAndVerticalYaw() {
    let minimum = SIMD3<Float>(-2, -0.2, -1)
    let maximum = SIMD3<Float>(1, 2.3, 5)
    let normalization = CharacterModelNormalization(minimum: minimum, maximum: maximum)!
    let foot = SIMD3<Float>(-0.5, -0.2, 2)
    XCTAssertEqual(normalization.scale * 6, 0.35, accuracy: 0.00001)
    for scale: Float in [0.5, 1, 1.5] {
      for yaw: Float in [-.pi, -.pi / 2, 0, .pi / 2, .pi] {
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let transformed = rotation.act((foot * normalization.scale + normalization.translation) * scale)
        XCTAssertLessThan(simd_length(transformed), 0.00001)
        let up = rotation.act(SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(up, SIMD3<Float>(0, 1, 0))
      }
    }
    XCTAssertNil(CharacterModelNormalization(minimum: minimum, maximum: minimum))
    XCTAssertNil(CharacterModelNormalization(minimum: maximum, maximum: minimum))
    XCTAssertNil(CharacterModelNormalization(minimum: SIMD3(.nan, 0, 0), maximum: maximum))
    XCTAssertNil(CharacterModelNormalization(minimum: .zero,
      maximum: SIMD3(repeating: Float.leastNonzeroMagnitude)))
  }

  func testAnimationPlaybackGatesIdleAndSpeakingButHoldsPausedAndInterrupted() {
    for state in [CharacterPresentationState.idle, .speaking, .paused] {
      XCTAssertEqual(CharacterAnimationPolicy.shouldPlay(state: state, placement: .placed,
        active: true, interrupted: false, failed: false, recovering: false), state != .paused)
      for placement in [CharacterPlacementState.searching, .moving] {
        XCTAssertFalse(CharacterAnimationPolicy.shouldPlay(state: state, placement: placement,
          active: true, interrupted: false, failed: false, recovering: false))
      }
      XCTAssertFalse(CharacterAnimationPolicy.shouldPlay(state: state, placement: .placed,
        active: false, interrupted: false, failed: false, recovering: false))
      XCTAssertFalse(CharacterAnimationPolicy.shouldPlay(state: state, placement: .placed,
        active: true, interrupted: true, failed: false, recovering: false))
      XCTAssertFalse(CharacterAnimationPolicy.shouldPlay(state: state, placement: .placed,
        active: true, interrupted: false, failed: true, recovering: false))
      XCTAssertFalse(CharacterAnimationPolicy.shouldPlay(state: state, placement: .placed,
        active: true, interrupted: false, failed: false, recovering: true))
    }
  }

  func testExperimentalCapabilitiesRequireIndependentOptInAvailabilityAndSupport() {
    for api in [false, true] {
      for support in [false, true] {
        for requested in [false, true] {
          XCTAssertEqual(CharacterExperimentalCapability(apiAvailable: api, supported: support,
            requested: requested).configured, api && support && requested)
        }
      }
    }
    let room = CharacterExperimentalCapability(apiAvailable: true, supported: false, requested: true)
    let people = CharacterExperimentalCapability(apiAvailable: true, supported: true, requested: false)
    XCTAssertFalse(room.configured)
    XCTAssertFalse(people.configured) // Neither infers the other's support or enables it.
  }

  func testViewerFacingUsesHorizontalDirectionNotCameraHeight() {
    let position = SIMD3<Float>(0, 0, 0)
    XCTAssertEqual(CharacterAssetPresentation.viewerYaw(position: position,
      camera: SIMD3(1, 20, 0)), .pi / 2, accuracy: 0.0001)
    XCTAssertEqual(CharacterAssetPresentation.viewerYaw(position: position,
      camera: SIMD3(0, -2, 1)), 0, accuracy: 0.0001)
    XCTAssertEqual(CharacterAssetPresentation.viewerYaw(position: position, camera: position), 0)
  }

  @MainActor
  func testControlsFitNarrowAndLandscapeScreensAtAccessibilityTypeSize() {
    for size in [CGSize(width: 320, height: 568), CGSize(width: 812, height: 375),
                 CGSize(width: 768, height: 1024)] {
      let parent = UIViewController()
      let reader = CharacterReaderViewController(pages: [], initialPageIndex: 0,
        storyMode: true, onComplete: { _ in })
      parent.addChild(reader)
      parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory:
        .accessibilityExtraExtraExtraLarge), forChild: reader)
      parent.view.frame = CGRect(origin: .zero, size: size)
      parent.view.addSubview(reader.view)
      reader.view.frame = parent.view.bounds
      reader.didMove(toParent: parent)
      let buttons = descendants(reader.view).compactMap { $0 as? UIButton }
      for suffix in ["smaller", "larger", "turnLeft", "turnRight", "resetAdjustment"] {
        let button = buttons.first { $0.accessibilityIdentifier == "reader.\(suffix)" }
        XCTAssertNotNil(button)
        XCTAssertFalse((button?.accessibilityHint ?? "").isEmpty)
      }
      for button in buttons { button.isHidden = false }
      reader.view.setNeedsLayout()
      reader.view.layoutIfNeeded()
      let scroll = descendants(reader.view).first { $0.accessibilityIdentifier == "reader.controls" } as! UIScrollView
      scroll.layoutIfNeeded()
      XCTAssertGreaterThan(scroll.bounds.height, 0)
      XCTAssertLessThanOrEqual(scroll.frame.maxX, size.width)
      XCTAssertLessThanOrEqual(scroll.frame.maxY, size.height)
      XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
      for button in buttons {
        XCTAssertGreaterThanOrEqual(button.bounds.height, 48)
        XCTAssertLessThanOrEqual(button.bounds.width, size.width)
        XCTAssertTrue(button.titleLabel?.adjustsFontForContentSizeCategory == true)
        XCTAssertFalse((button.title(for: .normal) ?? "").isEmpty)
      }
    }
  }

  private func eligibility(normal: Bool, tracked: Bool, up: Float) -> CharacterPlacementEligibility {
    CharacterPlacementEligibility.evaluate(normalTracking: normal, hasHit: true,
      trackedPlane: tracked, upwardNormal: up)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }
}
