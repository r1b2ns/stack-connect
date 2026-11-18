import XCTest
@testable import StackConnect

final class BundleIdPlatformLabelTests: XCTestCase {

    func testShortLabelsForKnownPlatforms() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "IOS"), "iOS")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "MAC_OS"), "macOS")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "UNIVERSAL"), "Universal")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "SERVICES"), "Services")
    }

    func testExpandedIOSLabelListsEveryCoveredOS() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "IOS", style: .expanded), "iOS, tvOS, watchOS, visionOS")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "MAC_OS", style: .expanded), "macOS")
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "ios"), "iOS")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "mac_os"), "macOS")
    }

    func testUnknownValueFallsBackToRaw() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "VISION_OS"), "VISION_OS")
    }

    func testNilOrEmptyShowsDash() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: String?.none), "—")
        XCTAssertEqual(BundleIdPlatformLabel.label(for: Optional("")), "—")
    }

    func testModelsUseSharedMapping() {
        let bundle = BundleIdentifierModel(id: "1", identifier: "com.a", name: "A", platform: "MAC_OS", seedId: nil)
        XCTAssertEqual(bundle.platformDisplayName, "macOS")
        let device = DeviceModel(id: "1", name: "D", udid: nil, platform: nil, deviceClass: nil, model: nil, status: "ENABLED", addedDate: nil)
        XCTAssertEqual(device.platformDisplayName, "—")
    }
}
