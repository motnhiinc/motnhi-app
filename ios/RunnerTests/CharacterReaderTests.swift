import Foundation
import XCTest
@testable import Runner

final class CharacterReaderTests: XCTestCase {
  private let fileManager = FileManager.default
  private var rootDirectory: URL!
  private var allowedDirectory: URL!

  override func setUpWithError() throws {
    rootDirectory = fileManager.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    allowedDirectory = rootDirectory.appendingPathComponent("app-temp", isDirectory: true)
    try fileManager.createDirectory(at: allowedDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? fileManager.removeItem(at: rootDirectory)
  }

  func testAcceptsExactNarrationFileBelowResolvedTemporaryDirectory() throws {
    let nestedDirectory = allowedDirectory.appendingPathComponent("nested", isDirectory: true)
    try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    let audioURL = nestedDirectory.appendingPathComponent("scan_any_page_narration.mp3")
    try Data([0x01]).write(to: audioURL)

    let result = CharacterReaderAudioPathValidator(
      temporaryDirectory: allowedDirectory
    ).validate(path: audioURL.path)

    XCTAssertEqual(result, audioURL.resolvingSymlinksInPath().standardizedFileURL)
  }

  func testRejectsWrongFilenameAndSiblingPrefixDirectory() throws {
    let wrongName = allowedDirectory.appendingPathComponent("narration.mp3")
    try Data([0x01]).write(to: wrongName)
    let sibling = rootDirectory.appendingPathComponent("app-temp-escape", isDirectory: true)
    try fileManager.createDirectory(at: sibling, withIntermediateDirectories: true)
    let siblingAudio = sibling.appendingPathComponent("scan_any_page_narration.mp3")
    try Data([0x01]).write(to: siblingAudio)
    let validator = CharacterReaderAudioPathValidator(temporaryDirectory: allowedDirectory)

    XCTAssertNil(validator.validate(path: wrongName.path))
    XCTAssertNil(validator.validate(path: siblingAudio.path))
  }

  func testRejectsSymlinkThatEscapesTemporaryDirectory() throws {
    let outsideDirectory = rootDirectory.appendingPathComponent("outside", isDirectory: true)
    try fileManager.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
    let outsideAudio = outsideDirectory.appendingPathComponent("scan_any_page_narration.mp3")
    try Data([0x01]).write(to: outsideAudio)
    let link = allowedDirectory.appendingPathComponent("scan_any_page_narration.mp3")
    try fileManager.createSymbolicLink(at: link, withDestinationURL: outsideAudio)

    let result = CharacterReaderAudioPathValidator(
      temporaryDirectory: allowedDirectory
    ).validate(path: link.path)

    XCTAssertNil(result)
  }

  func testRejectsDirectoryWithExpectedFilename() throws {
    let directory = allowedDirectory.appendingPathComponent(
      "scan_any_page_narration.mp3",
      isDirectory: true
    )
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let result = CharacterReaderAudioPathValidator(
      temporaryDirectory: allowedDirectory
    ).validate(path: directory.path)

    XCTAssertNil(result)
  }

  func testPlayingPlaybackPausesForInterruption() {
    var state = CharacterReaderPlaybackState.playing

    XCTAssertTrue(state.pauseForInterruption())
    XCTAssertEqual(state, .paused)
  }

  func testRetryPlaybackIsPreservedDuringInterruption() {
    var state = CharacterReaderPlaybackState.retry

    XCTAssertFalse(state.pauseForInterruption())
    XCTAssertEqual(state, .retry)
  }
}
