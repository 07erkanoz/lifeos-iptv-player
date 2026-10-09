import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testLocalNetworkDiscoveryIsDeclared() {
    let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] ?? []
    XCTAssertTrue(services.contains("_googlecast._tcp"))
    XCTAssertTrue(services.contains("_lifeostv-sync._tcp"))
  }
  func testPrivacyUsageDescriptionsArePresent() {
    for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSLocalNetworkUsageDescription"] {
      let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
      XCTAssertFalse(value.isEmpty, key)
    }
  }
  func testPhoneAllowsPortraitAndLandscapePlayback() {
    let orientations = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String] ?? []
    XCTAssertTrue(orientations.contains("UIInterfaceOrientationPortrait"))
    XCTAssertTrue(orientations.contains("UIInterfaceOrientationLandscapeLeft"))
    XCTAssertTrue(orientations.contains("UIInterfaceOrientationLandscapeRight"))
  }
}
