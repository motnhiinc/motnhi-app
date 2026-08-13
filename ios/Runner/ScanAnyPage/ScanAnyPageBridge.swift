import Flutter
import UIKit

final class ScanAnyPageBridge {
  private weak var flutterViewController: FlutterViewController?
  private let channel: FlutterMethodChannel
  private var isScanInProgress = false

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
    guard call.method == "scanAndRecognize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard !isScanInProgress else {
      result(FlutterError(code: "scan_in_progress", message: nil, details: nil))
      return
    }
    guard let flutterViewController, flutterViewController.presentedViewController == nil else {
      result(FlutterError(code: "camera_unavailable", message: nil, details: nil))
      return
    }

    isScanInProgress = true
    let scanner = PageScannerViewController()
    scanner.modalPresentationStyle = .fullScreen
    var didResolve = false
    scanner.onComplete = { [weak self, weak scanner] scanResult in
      guard let self, !didResolve else { return }
      didResolve = true

      let resolve = {
        self.isScanInProgress = false
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
    flutterViewController.present(scanner, animated: true)
  }
}
