import CoreGraphics

struct NormalizedQuad: Equatable {
  let topLeft: CGPoint
  let topRight: CGPoint
  let bottomLeft: CGPoint
  let bottomRight: CGPoint

  var area: CGFloat {
    let points = [topLeft, topRight, bottomRight, bottomLeft]
    let doubledArea = zip(points, points.dropFirst() + [points[0]]).reduce(CGFloat.zero) {
      $0 + ($1.0.x * $1.1.y) - ($1.1.x * $1.0.y)
    }
    return abs(doubledArea) / 2
  }

  func maximumCornerDistance(to other: NormalizedQuad) -> CGFloat {
    zip(corners, other.corners).map { lhs, rhs in
      hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }.max() ?? 0
  }

  func imagePoints(in extent: CGRect) -> NormalizedQuad {
    func convert(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: extent.minX + point.x * extent.width,
        y: extent.minY + point.y * extent.height
      )
    }

    return NormalizedQuad(
      topLeft: convert(topLeft),
      topRight: convert(topRight),
      bottomLeft: convert(bottomLeft),
      bottomRight: convert(bottomRight)
    )
  }

  static func unitInset(_ inset: CGFloat) -> NormalizedQuad {
    NormalizedQuad(
      topLeft: CGPoint(x: inset, y: 1 - inset),
      topRight: CGPoint(x: 1 - inset, y: 1 - inset),
      bottomLeft: CGPoint(x: inset, y: inset),
      bottomRight: CGPoint(x: 1 - inset, y: inset)
    )
  }

  private var corners: [CGPoint] {
    [topLeft, topRight, bottomLeft, bottomRight]
  }
}

/// One camera instruction at a time; capture eligibility remains with the
/// separate stability and focus tracker.
enum ScanGuidance: Equatable {
  case findPage
  case moveCloser
  case holdStill

  static func forPage(_ quad: NormalizedQuad?, minimumArea: CGFloat) -> ScanGuidance {
    guard let quad else { return .findPage }
    return quad.area < minimumArea ? .moveCloser : .holdStill
  }
}

struct OneShotGate {
  private var isClaimed = false

  mutating func claim() -> Bool {
    guard !isClaimed else { return false }
    isClaimed = true
    return true
  }
}

struct ScannerLifecycleState<Terminal> {
  private(set) var isCapturing = false
  private(set) var terminal: Terminal?

  var isTerminal: Bool {
    terminal != nil
  }

  mutating func beginCapture() -> Bool {
    guard !isCapturing, !isTerminal else { return false }
    isCapturing = true
    return true
  }

  mutating func finish(_ terminal: Terminal) -> Bool {
    guard !isTerminal else { return false }
    self.terminal = terminal
    return true
  }
}

struct RectangleStabilityTracker {
  let requiredStableFrames: Int
  let tolerance: CGFloat
  let minimumArea: CGFloat

  private var previousQuad: NormalizedQuad?
  private var stableFrameCount = 0

  init(requiredStableFrames: Int, tolerance: CGFloat, minimumArea: CGFloat) {
    self.requiredStableFrames = requiredStableFrames
    self.tolerance = tolerance
    self.minimumArea = minimumArea
  }

  mutating func observe(_ quad: NormalizedQuad?, qualityAcceptable: Bool) -> Bool {
    guard qualityAcceptable, let quad, quad.area >= minimumArea else {
      reset()
      return false
    }

    if let previousQuad, quad.maximumCornerDistance(to: previousQuad) <= tolerance {
      stableFrameCount += 1
    } else {
      stableFrameCount = 1
    }
    self.previousQuad = quad
    return stableFrameCount >= requiredStableFrames
  }

  mutating func reset() {
    previousQuad = nil
    stableFrameCount = 0
  }
}
