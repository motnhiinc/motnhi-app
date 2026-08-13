import CoreGraphics
import XCTest
@testable import Runner

final class ScanGeometryTests: XCTestCase {
  func testMapsVisionCoordinatesIntoNormalizedImageExtentWithoutFlipping() {
    let quad = NormalizedQuad(
      topLeft: CGPoint(x: 0.1, y: 0.9),
      topRight: CGPoint(x: 0.8, y: 0.85),
      bottomLeft: CGPoint(x: 0.2, y: 0.15),
      bottomRight: CGPoint(x: 0.75, y: 0.1)
    )

    let points = quad.imagePoints(in: CGRect(x: 10, y: 20, width: 200, height: 100))

    XCTAssertEqual(points.topLeft, CGPoint(x: 30, y: 110))
    XCTAssertEqual(points.topRight, CGPoint(x: 170, y: 105))
    XCTAssertEqual(points.bottomLeft, CGPoint(x: 50, y: 35))
    XCTAssertEqual(points.bottomRight, CGPoint(x: 160, y: 30))
  }

  func testOneShotGateCanOnlyBeClaimedOnce() {
    var gate = OneShotGate()

    XCTAssertTrue(gate.claim())
    XCTAssertFalse(gate.claim())
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
}
