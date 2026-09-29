import CoreGraphics

struct RecognizedLine: Equatable {
  let text: String
  let boundingBox: CGRect
}

enum TextObservationSorter {
  private static let rowTolerance: CGFloat = 0.02

  static func ordered(_ lines: [RecognizedLine]) -> [RecognizedLine] {
    var rows: [[RecognizedLine]] = []

    for line in lines.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
      if let index = rows.firstIndex(where: { row in
        guard let first = row.first else { return false }
        return abs(first.boundingBox.midY - line.boundingBox.midY) <= rowTolerance
      }) {
        rows[index].append(line)
      } else {
        rows.append([line])
      }
    }

    return rows
      .sorted { ($0.first?.boundingBox.midY ?? 0) > ($1.first?.boundingBox.midY ?? 0) }
      .flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
  }

  static func join(_ lines: [RecognizedLine]) -> String {
    ordered(lines)
      .map(\.text)
      .joined(separator: "\n")
  }

  static func topLeftNormalizedBox(_ box: CGRect) -> CGRect? {
    guard box.minX >= 0, box.minY >= 0, box.width > 0, box.height > 0,
          box.maxX <= 1, box.maxY <= 1 else { return nil }
    return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
  }
}
