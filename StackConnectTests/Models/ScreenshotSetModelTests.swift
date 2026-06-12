import XCTest
@testable import StackConnect

final class ScreenshotSetModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSet(displayType: String?) -> ScreenshotSetModel {
        ScreenshotSetModel(id: "set-1", displayType: displayType)
    }

    // MARK: - Known display types

    func testDeviceCategoryMapsIPhone() {
        XCTAssertEqual(makeSet(displayType: "APP_IPHONE_67").deviceCategory, .iPhone)
    }

    func testDeviceCategoryMapsIPad() {
        XCTAssertEqual(makeSet(displayType: "APP_IPAD_PRO_3GEN_129").deviceCategory, .iPad)
    }

    func testDeviceCategoryMapsAppleWatch() {
        XCTAssertEqual(makeSet(displayType: "APP_WATCH_SERIES_7").deviceCategory, .appleWatch)
    }

    func testDeviceCategoryMapsIMessage() {
        XCTAssertEqual(makeSet(displayType: "IMESSAGE_APP_IPHONE_67").deviceCategory, .iMessage)
    }

    func testDeviceCategoryMapsAppleTV() {
        XCTAssertEqual(makeSet(displayType: "APP_APPLE_TV").deviceCategory, .appleTV)
    }

    func testDeviceCategoryMapsMac() {
        XCTAssertEqual(makeSet(displayType: "APP_DESKTOP").deviceCategory, .mac)
    }

    func testDeviceCategoryMapsVisionPro() {
        XCTAssertEqual(makeSet(displayType: "APP_APPLE_VISION_PRO").deviceCategory, .visionPro)
    }

    // MARK: - Prefix-collision guard

    /// `APP_APPLE_TV` and `APP_APPLE_VISION` both start with `APP_APPLE`.
    /// Ensure neither swallows the other.
    func testAppleTVAndVisionProDoNotCollide() {
        XCTAssertEqual(makeSet(displayType: "APP_APPLE_TV").deviceCategory, .appleTV)
        XCTAssertEqual(makeSet(displayType: "APP_APPLE_VISION_PRO").deviceCategory, .visionPro)
    }

    // MARK: - Unknown / nil

    func testDeviceCategoryNilWhenDisplayTypeIsNil() {
        XCTAssertNil(makeSet(displayType: nil).deviceCategory)
    }

    func testDeviceCategoryNilForUnknownPrefix() {
        XCTAssertNil(makeSet(displayType: "APP_FUTURE_DEVICE").deviceCategory)
    }
}
