// Read-only runtime resource inventory; not an animation/visual acceptance test.
// xcrun swiftc -parse-as-library tools/ar_enumerate_realitykit.swift -o /path/to/ar-enumerate
// /path/to/ar-enumerate ios/Runner/CharacterReader/*.usdz > /path/to/inventory.json
import CryptoKit
import Foundation
import RealityKit

@main
struct CharacterAnimationInventory {
  @MainActor
  static func main() throws {
    let paths = Array(CommandLine.arguments.dropFirst())
    guard !paths.isEmpty else {
      throw NSError(domain: "ARAnimationInventory", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Supply one or more USDZ files"])
    }
    var files: [[String: Any]] = []
    for path in paths {
      let url = URL(fileURLWithPath: path)
      let entity = try Entity.load(contentsOf: url)
      var resources: [[String: Any]] = []
      collect(entity, ownerPath: [], into: &resources)
      let digest = SHA256.hash(data: try Data(contentsOf: url))
        .map { String(format: "%02x", $0) }.joined()
      files.append(["file": url.lastPathComponent, "sha256": digest,
        "resources": resources])
    }
    let report: [String: Any] = [
      "format_version": 1,
      "runtime_platform": "macOS",
      "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
      "visual_acceptance": "UNVERIFIED",
      "limitation": "macOS Entity.load resource names do not certify physical iOS rendering; the reader independently validates owner/name/duration at runtime.",
      "files": files,
    ]
    let data = try JSONSerialization.data(withJSONObject: report,
      options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  @MainActor
  static func collect(_ entity: Entity, ownerPath: [String], into resources: inout [[String: Any]]) {
    let path = ownerPath + [entity.name]
    for animation in entity.availableAnimations {
      let probe = entity.playAnimation(animation, startsPaused: true)
      let duration = probe.duration
      probe.stop()
      resources.append(["owner_path": path, "name": animation.name as Any? ?? NSNull(),
        "duration_seconds": duration])
    }
    for child in entity.children {
      collect(child, ownerPath: path, into: &resources)
    }
  }
}
