import CoreGraphics
import XCTest
@testable import Runner

final class ScanGeometryTests: XCTestCase {
  func testVisionBoxConvertsToTopLeftNormalizedCoordinates() {
    let box = TextObservationSorter.topLeftNormalizedBox(
      CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2)
    )
    XCTAssertNotNil(box)
    XCTAssertEqual(box?.minX ?? -1, 0.1, accuracy: 0.0001)
    XCTAssertEqual(box?.minY ?? -1, 0.1, accuracy: 0.0001)
    XCTAssertEqual(box?.width ?? -1, 0.8, accuracy: 0.0001)
    XCTAssertEqual(box?.height ?? -1, 0.2, accuracy: 0.0001)
  }

  func testRejectsInvalidOrOutOfBoundsVisionBoxes() {
    XCTAssertNil(TextObservationSorter.topLeftNormalizedBox(
      CGRect(x: 0.2, y: 0.7, width: 0.9, height: 0.2)
    ))
    XCTAssertNil(TextObservationSorter.topLeftNormalizedBox(
      CGRect(x: 0.2, y: 0.2, width: 0, height: 0.2)
    ))
  }

  private enum Terminal: Equatable {
    case success
    case cancelled
    case failure
  }

  // Vision and Core Image share bottom-left coordinates after EXIF normalization,
  // so this pure boundary is deterministic without testing OS rectangle recognition.
  func testMapsAllCornersIntoPortraitStillExtentWithoutFlipping() {
    let quad = NormalizedQuad(
      topLeft: CGPoint(x: 0.1, y: 0.9),
      topRight: CGPoint(x: 0.8, y: 0.85),
      bottomLeft: CGPoint(x: 0.2, y: 0.15),
      bottomRight: CGPoint(x: 0.75, y: 0.1)
    )

    let points = quad.imagePoints(in: CGRect(x: 10, y: 20, width: 100, height: 240))

    XCTAssertEqual(points.topLeft, CGPoint(x: 20, y: 236))
    XCTAssertEqual(points.topRight, CGPoint(x: 90, y: 224))
    XCTAssertEqual(points.bottomLeft, CGPoint(x: 30, y: 56))
    XCTAssertEqual(points.bottomRight, CGPoint(x: 85, y: 44))
  }

  func testMapsAllCornersIntoAsymmetricLandscapeStillExtentWithoutFlipping() {
    let quad = NormalizedQuad(
      topLeft: CGPoint(x: 0.05, y: 0.95),
      topRight: CGPoint(x: 0.9, y: 0.8),
      bottomLeft: CGPoint(x: 0.15, y: 0.2),
      bottomRight: CGPoint(x: 0.85, y: 0.05)
    )

    let points = quad.imagePoints(in: CGRect(x: 20, y: 30, width: 320, height: 120))

    XCTAssertEqual(points.topLeft, CGPoint(x: 36, y: 144))
    XCTAssertEqual(points.topRight, CGPoint(x: 308, y: 126))
    XCTAssertEqual(points.bottomLeft, CGPoint(x: 68, y: 54))
    XCTAssertEqual(points.bottomRight, CGPoint(x: 292, y: 36))
  }

  func testOneShotGateCanOnlyBeClaimedOnce() {
    var gate = OneShotGate()

    XCTAssertTrue(gate.claim())
    XCTAssertFalse(gate.claim())
  }

  func testLifecycleRejectsDuplicateCompletionAndPreservesFirstTerminalResult() {
    var lifecycle = ScannerLifecycleState<Terminal>()

    XCTAssertTrue(lifecycle.finish(.success))
    XCTAssertFalse(lifecycle.finish(.failure))
    XCTAssertEqual(lifecycle.terminal, .success)
  }

  func testCancellationWinsWhenItArrivesBeforeFailure() {
    var lifecycle = ScannerLifecycleState<Terminal>()

    XCTAssertTrue(lifecycle.finish(.cancelled))
    XCTAssertFalse(lifecycle.finish(.failure))
    XCTAssertEqual(lifecycle.terminal, .cancelled)
  }

  func testFailureWinsWhenItArrivesBeforeCancellation() {
    var lifecycle = ScannerLifecycleState<Terminal>()

    XCTAssertTrue(lifecycle.finish(.failure))
    XCTAssertFalse(lifecycle.finish(.cancelled))
    XCTAssertEqual(lifecycle.terminal, .failure)
  }

  func testLifecycleAllowsOneCaptureAndNoneAfterCompletion() {
    var lifecycle = ScannerLifecycleState<Terminal>()

    XCTAssertTrue(lifecycle.beginCapture())
    XCTAssertFalse(lifecycle.beginCapture())
    XCTAssertTrue(lifecycle.finish(.cancelled))
    XCTAssertFalse(lifecycle.beginCapture())
  }

  func testCapturesOnlyAfterRequiredStableFrames() {
    var tracker = RectangleStabilityTracker(
      requiredStableFrames: 3,
      tolerance: 0.02,
      minimumArea: 0.35
    )
    let quad = NormalizedQuad.unitInset(0.1)

    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertTrue(tracker.observe(quad, qualityAcceptable: true))
  }

  func testMovementAndBadQualityResetStability() {
    var tracker = RectangleStabilityTracker(
      requiredStableFrames: 3,
      tolerance: 0.02,
      minimumArea: 0.35
    )
    let quad = NormalizedQuad.unitInset(0.1)
    let movedQuad = NormalizedQuad(
      topLeft: CGPoint(x: 0.15, y: 0.9),
      topRight: CGPoint(x: 0.95, y: 0.9),
      bottomLeft: CGPoint(x: 0.15, y: 0.1),
      bottomRight: CGPoint(x: 0.95, y: 0.1)
    )

    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(movedQuad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(movedQuad, qualityAcceptable: false))
    XCTAssertFalse(tracker.observe(movedQuad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(movedQuad, qualityAcceptable: true))
    XCTAssertTrue(tracker.observe(movedQuad, qualityAcceptable: true))
  }

  func testSmallRectangleNeverCaptures() {
    var tracker = RectangleStabilityTracker(
      requiredStableFrames: 3,
      tolerance: 0.02,
      minimumArea: 0.35
    )
    let quad = NormalizedQuad.unitInset(0.3)

    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
    XCTAssertFalse(tracker.observe(quad, qualityAcceptable: true))
  }

  func testCameraCueFollowsPageDetectionAndSize() {
    XCTAssertEqual(ScanGuidance.forPage(nil, minimumArea: 0.35), .findPage)
    XCTAssertEqual(ScanGuidance.forPage(.unitInset(0.3), minimumArea: 0.35), .moveCloser)
    XCTAssertEqual(ScanGuidance.forPage(.unitInset(0.1), minimumArea: 0.35), .holdStill)
  }
}
