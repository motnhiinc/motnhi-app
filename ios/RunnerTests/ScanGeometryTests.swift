import CoreGraphics
import XCTest
@testable import Runner

final class ScanGeometryTests: XCTestCase {
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
