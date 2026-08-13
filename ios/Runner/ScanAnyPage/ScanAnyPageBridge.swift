import Flutter
import UIKit

final class ScanAnyPageBridge {
  private weak var flutterViewController: FlutterViewController?
  private let channel: FlutterMethodChannel
  private var isScanInProgress = false
  private var activeScanner: PageScannerViewController?

  init(flutterViewController: FlutterViewController, messenger: FlutterBinaryMessenger) {
    self.flutterViewController = flutterViewController
    channel = FlutterMethodChannel(
      name: "storybook_ar/scan_any_page",
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
    guard call.method == "scanAndRecognize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard !isScanInProgress else {
      result(FlutterError(code: "scan_in_progress", message: nil, details: nil))
      return
    }
    guard
      let flutterViewController,
      flutterViewController.viewIfLoaded?.window != nil,
      flutterViewController.presentedViewController == nil
    else {
      result(FlutterError(code: "camera_unavailable", message: nil, details: nil))
      return
    }

    isScanInProgress = true
    let scanner = PageScannerViewController()
    activeScanner = scanner
    scanner.modalPresentationStyle = .fullScreen
    var resultGate = OneShotGate()
    scanner.onComplete = { [weak self, weak scanner] scanResult in
      guard resultGate.claim() else { return }

      let resolve = {
        self?.isScanInProgress = false
        self?.activeScanner = nil
        switch scanResult {
        case .success(let text):
          result(["text": text])
        case .failure(let failure):
          result(FlutterError(code: failure.rawValue, message: nil, details: nil))
        }
      }
      if let scanner, scanner.presentingViewController != nil {
        scanner.dismiss(animated: true, completion: resolve)
      } else {
        resolve()
      }
    }
    flutterViewController.present(scanner, animated: true) { [weak scanner] in
      guard let scanner, scanner.presentingViewController == nil else { return }
      scanner.failPresentation()
    }
    DispatchQueue.main.async { [weak scanner] in
      guard let scanner, scanner.presentingViewController == nil else { return }
      scanner.failPresentation()
    }
  }
}
