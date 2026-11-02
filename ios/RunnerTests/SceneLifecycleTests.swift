import Flutter
import UIKit
import XCTest
@testable import Runner

final class SceneLifecycleTests: XCTestCase {
  func testStoryboardSceneOwnsBothNativeBridges() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let delegate = try XCTUnwrap(scene.delegate as? SceneDelegate)
    XCTAssertTrue(delegate.window?.rootViewController is FlutterViewController)
    XCTAssertNotNil(delegate.scanAnyPageBridge)
    XCTAssertNotNil(delegate.characterReaderBridge)
  }

  func testSceneActivationDoesNotReplaceChannelsOrPendingResults() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let delegate = try XCTUnwrap(scene.delegate as? SceneDelegate)
    let scanner = try XCTUnwrap(delegate.scanAnyPageBridge)
    let reader = try XCTUnwrap(delegate.characterReaderBridge)
    delegate.sceneWillResignActive(scene)
    delegate.sceneDidBecomeActive(scene)
    XCTAssertTrue(delegate.scanAnyPageBridge === scanner)
    XCTAssertTrue(delegate.characterReaderBridge === reader)
  }

  func testSceneManifestUsesSingleMainStoryboardScene() throws {
    let manifest = try XCTUnwrap(Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any])
    XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
    let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
    let scenes = try XCTUnwrap(configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
    XCTAssertEqual(scenes.count, 1)
    XCTAssertEqual(scenes.first?["UISceneStoryboardFile"] as? String, "Main")
    XCTAssertEqual(scenes.first?["UISceneDelegateClassName"] as? String, "Runner.SceneDelegate")
  }
}
