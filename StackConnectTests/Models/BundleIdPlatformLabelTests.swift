import XCTest
@testable import StackConnect

final class BundleIdPlatformLabelTests: XCTestCase {

    // Expected labels are localized like production, so the assertions hold in any simulator locale.

    func testShortLabelsForKnownPlatforms() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "IOS"), String(localized: "iOS"))
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "MAC_OS"), String(localized: "macOS"))
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "UNIVERSAL"), String(localized: "Universal"))
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "SERVICES"), String(localized: "Services"))
    }

    func testExpandedIOSLabelListsEveryCoveredOS() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "IOS", style: .expanded), String(localized: "iOS, tvOS, watchOS, visionOS"))
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "MAC_OS", style: .expanded), String(localized: "macOS"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "ios"), String(localized: "iOS"))
        XCTAssertEqual(BundleIdPlatformLabel.label(for: "mac_os"), String(localized: "macOS"))
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
        XCTAssertEqual(bundle.platformDisplayName, String(localized: "macOS"))
        let device = DeviceModel(id: "1", name: "D", udid: nil, platform: nil, deviceClass: nil, model: nil, status: "ENABLED", addedDate: nil)
        XCTAssertEqual(device.platformDisplayName, "—")
    }
}
