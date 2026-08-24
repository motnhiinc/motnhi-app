import ARKit
import Flutter
import UIKit

struct CharacterReaderAudioPathValidator {
  /// The single-clip name the scan-any-page flow has always used.
  private static let expectedFilename = "scan_any_page_narration.mp3"

  /// Per-segment clips prepared for the story reader:
  /// `ar_<sanitizedStoryId>_p<pageNumber>_s<sortOrder>.<ext>`.
  ///
  /// Anchored deliberately: an unanchored pattern would also accept
  /// `evil_ar_abc_p1_s0.mp3`. `caf` is in the set because iOS cannot encode mp3,
  /// so device speech synthesis writes CoreAudio Format here.
  private static let storySegmentFilename =
    #"^ar_[A-Za-z0-9]{1,32}_p[0-9]{1,4}_s[0-9]{1,4}\.(mp3|wav|caf|m4a)$"#

  static func isAllowedName(_ name: String) -> Bool {
    if name == expectedFilename { return true }
    return name.range(of: storySegmentFilename, options: [.regularExpression]) != nil
  }

  let temporaryDirectory: URL

  func validate(path: String) -> URL? {
    guard !path.isEmpty, NSString(string: path).isAbsolutePath else { return nil }

    let resolvedTemporaryDirectory = temporaryDirectory
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let requestedURL = URL(fileURLWithPath: path).standardizedFileURL
    let resolvedURL = requestedURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let temporaryComponents = resolvedTemporaryDirectory.pathComponents
    let candidateComponents = resolvedURL.pathComponents
    guard
      Self.isAllowedName(requestedURL.lastPathComponent),
      // Checked again after symlink resolution: the pre-resolution name is
      // caller-supplied, and a symlink with an allowed name can point elsewhere.
      Self.isAllowedName(resolvedURL.lastPathComponent),
      candidateComponents.count > temporaryComponents.count,
      candidateComponents.prefix(temporaryComponents.count).elementsEqual(temporaryComponents)
    else {
      return nil
    }

    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
      attributes[.type] as? FileAttributeType == .typeRegular,
      FileManager.default.isReadableFile(atPath: resolvedURL.path)
    else {
      return nil
    }
    return resolvedURL
  }
}

extension StoryReaderPage {
  /// Returns nil when the request is malformed or *any* path fails validation; the bridge maps
  /// that to `audio_missing`. Strict by design: a page that silently lost clips would leave the
  /// character standing mute on the table.
  static func parseAll(
    _ raw: Any?,
    validator: CharacterReaderAudioPathValidator
  ) -> [StoryReaderPage]? {
    guard let entries = raw as? [[String: Any]], !entries.isEmpty else { return nil }

    var pages: [StoryReaderPage] = []
    for entry in entries {
      guard
        let pageId = entry["pageId"] as? String,
        let pageNumber = entry["pageNumber"] as? Int,
        let paths = entry["audioFilePaths"] as? [String],
        !paths.isEmpty
      else { return nil }

      var urls: [URL] = []
      for path in paths {
        guard let url = validator.validate(path: path) else { return nil }
        urls.append(url)
      }
      pages.append(StoryReaderPage(pageId: pageId, pageNumber: pageNumber, audioURLs: urls))
    }
    return pages
  }
}

final class CharacterReaderBridge {
  private weak var flutterViewController: FlutterViewController?
  private let channel: FlutterMethodChannel
  private let audioPathValidator = CharacterReaderAudioPathValidator(
    temporaryDirectory: FileManager.default.temporaryDirectory
  )
  private var isReaderInProgress = false
  private var activeReader: CharacterReaderViewController?

  init(flutterViewController: FlutterViewController, messenger: FlutterBinaryMessenger) {
    self.flutterViewController = flutterViewController
    channel = FlutterMethodChannel(
      name: "storybook_ar/character_reader",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.handle(call, result: result)
      }
      return
    }
    switch call.method {
    // Deliberately outside the in-progress guard: a capability probe presents nothing, and the
    // player asks it once on open so an unsupported device never shows the AR button and then
    // fails after a long narration preparation.
    case "isStoryReaderSupported":
      result(ARWorldTrackingConfiguration.isSupported)
    case "openCharacterReader":
      open(call, result: result, storyMode: false)
    case "openStoryReader":
      open(call, result: result, storyMode: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Shared entry for both readers. They share `isReaderInProgress` on purpose: they are the
  /// same channel and the same presentation slot, so two readers must never be presentable at
  /// once.
  private func open(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult,
    storyMode: Bool
  ) {
    guard !isReaderInProgress else {
      result(FlutterError(code: "reader_in_progress", message: nil, details: nil))
      return
    }

    let arguments = call.arguments as? [String: Any]
    let pages: [StoryReaderPage]
    var initialPageIndex = 0
    // Only the story-mode request names a variant. The parse happens here rather than inside
    // the branch because the reader is constructed below it; passing nil for the single-clip
    // flow keeps that reader on the original bundled character.
    let baseName = storyMode ? arguments?["modelAssetBaseName"] as? String : nil
    let safeModelBaseName = Self.safeModelAssetBaseName(baseName)

    if storyMode {
      guard
        let parsed = StoryReaderPage.parseAll(arguments?["pages"], validator: audioPathValidator)
      else {
        result(FlutterError(code: CharacterReaderFailure.audioMissing.rawValue, message: nil, details: nil))
        return
      }
      pages = parsed
      initialPageIndex = min(max(arguments?["initialPageIndex"] as? Int ?? 0, 0), parsed.count - 1)
    } else {
      guard
        let path = arguments?["audioFilePath"] as? String,
        let audioURL = audioPathValidator.validate(path: path)
      else {
        result(FlutterError(code: CharacterReaderFailure.audioMissing.rawValue, message: nil, details: nil))
        return
      }
      pages = [StoryReaderPage(pageId: "", pageNumber: 1, audioURLs: [audioURL])]
    }

    guard
      let flutterViewController,
      flutterViewController.viewIfLoaded?.window != nil,
      flutterViewController.presentedViewController == nil
    else {
      result(FlutterError(code: CharacterReaderFailure.arFailed.rawValue, message: nil, details: nil))
      return
    }

    isReaderInProgress = true
    var resultGate = OneShotGate()
    var reader: CharacterReaderViewController!
    reader = CharacterReaderViewController(
      pages: pages,
      initialPageIndex: initialPageIndex,
      storyMode: storyMode,
      modelAssetBaseName: safeModelBaseName
    ) { [weak self, weak reader] readerResult in
      guard resultGate.claim() else { return }
      let resolve = {
        self?.isReaderInProgress = false
        self?.activeReader = nil
        switch readerResult {
        case .completed(let progress):
          // Story mode replies on the success channel for BOTH terminal outcomes, unlike the
          // single-clip reader: cancel is the normal way to leave AR and it still carries the
          // page the child reached. FlutterError stays for failures that presented nothing.
          result(storyMode ? Self.payload("completed", progress) : "completed")
        case .cancelled(let progress):
          if storyMode {
            result(Self.payload("cancelled", progress))
          } else {
            result(FlutterError(code: "cancelled", message: nil, details: nil))
          }
        case .failure(let failure):
          result(FlutterError(code: failure.rawValue, message: nil, details: nil))
        }
      }
      if let reader, reader.presentingViewController != nil {
        reader.dismiss(animated: true, completion: resolve)
      } else {
        resolve()
      }
    }
    activeReader = reader
    reader.modalPresentationStyle = .fullScreen
    flutterViewController.present(reader, animated: true) { [weak reader] in
      guard let reader, reader.presentingViewController == nil else { return }
      reader.failPresentation()
    }
    DispatchQueue.main.async { [weak reader] in
      guard let reader, reader.presentingViewController == nil else { return }
      reader.failPresentation()
    }
  }

  /// Trust boundary, not styling: method-channel arguments must never become arbitrary
  /// bundle-resource lookups, so only an allowlisted `[a-z0-9_]` base name reaches
  /// `Bundle.main.url(forResource:)`. Anything else — a missing key, mixed case, or a
  /// smuggled path — falls back to the original scan-any-page character.
  private static func safeModelAssetBaseName(_ value: String?) -> String {
    guard let value,
          value.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
    else { return "scan_any_page_character" }
    return value
  }

  private static func payload(
    _ terminalCode: String,
    _ progress: CharacterReaderProgress
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "terminalCode": terminalCode,
      "pagesRead": progress.pagesRead,
    ]
    // NSNull rather than omission: the Dart side reads a nullable String and a missing key and
    // an explicit null must not behave differently.
    payload["lastPageId"] = progress.lastPageId ?? NSNull()
    return payload
  }

}
