import Flutter
import UIKit

struct CharacterReaderAudioPathValidator {
  private static let expectedFilename = "scan_any_page_narration.mp3"

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
      requestedURL.lastPathComponent == Self.expectedFilename,
      resolvedURL.lastPathComponent == Self.expectedFilename,
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
    guard call.method == "openCharacterReader" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard !isReaderInProgress else {
      result(FlutterError(code: "reader_in_progress", message: nil, details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["audioFilePath"] as? String,
      let audioURL = audioPathValidator.validate(path: path)
    else {
      result(FlutterError(code: CharacterReaderFailure.audioMissing.rawValue, message: nil, details: nil))
      return
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
    reader = CharacterReaderViewController(audioURL: audioURL) { [weak self, weak reader] readerResult in
      guard resultGate.claim() else { return }
      let resolve = {
        self?.isReaderInProgress = false
        self?.activeReader = nil
        switch readerResult {
        case .completed:
          result("completed")
        case .cancelled:
          result(FlutterError(code: "cancelled", message: nil, details: nil))
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

}
