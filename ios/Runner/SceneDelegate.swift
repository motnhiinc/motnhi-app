import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private weak var bridgeViewController: FlutterViewController?
  private(set) var scanAnyPageBridge: ScanAnyPageBridge?
  private(set) var characterReaderBridge: CharacterReaderBridge?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Main.storyboard supplies this scene's controller, not AppDelegate.window.
    // A reconnect with the same controller must preserve channels and pending results.
    guard let controller = window?.rootViewController as? FlutterViewController,
          controller !== bridgeViewController else { return }
    bridgeViewController = controller
    scanAnyPageBridge = ScanAnyPageBridge(
      flutterViewController: controller,
      messenger: controller.binaryMessenger
    )
    characterReaderBridge = CharacterReaderBridge(
      flutterViewController: controller,
      messenger: controller.binaryMessenger
    )
    // UIKit still posts UIApplication active/inactive notifications for this
    // single-scene app. Native controllers already observe those; reposting them
    // here would duplicate playback/AR lifecycle transitions.
  }
}
