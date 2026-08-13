import CoreGraphics

struct RecognizedLine: Equatable {
  let text: String
  let boundingBox: CGRect
}

enum TextObservationSorter {
  private static let rowTolerance: CGFloat = 0.02

  static func join(_ lines: [RecognizedLine]) -> String {
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
      .map(\.text)
      .joined(separator: "\n")
  }
}
