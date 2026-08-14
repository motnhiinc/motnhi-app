import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var scanAnyPageBridge: ScanAnyPageBridge?
  private var characterReaderBridge: CharacterReaderBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let flutterViewController = window?.rootViewController as? FlutterViewController {
      scanAnyPageBridge = ScanAnyPageBridge(
        flutterViewController: flutterViewController,
        messenger: flutterViewController.binaryMessenger
      )
      characterReaderBridge = CharacterReaderBridge(
        flutterViewController: flutterViewController,
        messenger: flutterViewController.binaryMessenger
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
