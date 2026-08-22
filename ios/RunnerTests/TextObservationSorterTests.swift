import CoreGraphics
import XCTest
@testable import Runner

final class TextObservationSorterTests: XCTestCase {
  func testSortsTopToBottomAndJoinsWithNewlines() {
    let lines = [
      RecognizedLine(text: "Bottom", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.08)),
      RecognizedLine(text: "Top", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.08)),
    ]

    XCTAssertEqual(TextObservationSorter.join(lines), "Top\nBottom")
  }

  func testSortsLeftToRightWithinSharedRow() {
    let lines = [
      RecognizedLine(text: "right", boundingBox: CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.1)),
      RecognizedLine(text: "left", boundingBox: CGRect(x: 0.1, y: 0.71, width: 0.2, height: 0.1)),
    ]

    XCTAssertEqual(TextObservationSorter.join(lines), "left\nright")
  }

  func testPreservesVietnameseDiacritics() {
    let lines = [
      RecognizedLine(
        text: "Chú thỏ ngắm ánh trăng.",
        boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
      ),
    ]

    XCTAssertEqual(TextObservationSorter.join(lines), "Chú thỏ ngắm ánh trăng.")
  }
}
