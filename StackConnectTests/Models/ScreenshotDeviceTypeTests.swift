import XCTest
@testable import StackConnect

final class ScreenshotDeviceTypeTests: XCTestCase {

    // MARK: - Per-case platform mapping

    func testIPhoneMapsToIOS() {
        XCTAssertEqual(ScreenshotDeviceType.iPhone.platform, .ios)
    }

    func testIPadMapsToIOS() {
        XCTAssertEqual(ScreenshotDeviceType.iPad.platform, .ios)
    }

    func testIMessageMapsToIOS() {
        XCTAssertEqual(ScreenshotDeviceType.iMessage.platform, .ios)
    }

    func testMacMapsToMacOS() {
        XCTAssertEqual(ScreenshotDeviceType.mac.platform, .macOs)
    }

    func testAppleTVMapsToTvOS() {
        XCTAssertEqual(ScreenshotDeviceType.appleTV.platform, .tvOs)
    }

    func testVisionProMapsToVisionOS() {
        XCTAssertEqual(ScreenshotDeviceType.visionPro.platform, .visionOs)
    }

    // MARK: - Filtering guard (powers `availableDeviceTypes`)

    func testIOSFilterYieldsIPhoneIPadIMessage() {
        let filtered = ScreenshotDeviceType.allCases.filter { $0.platform == .ios }
        XCTAssertEqual(Set(filtered), Set([.iPhone, .iPad, .iMessage, .appleWatch]))
    }

    func testMacOSFilterYieldsMacOnly() {
        let filtered = ScreenshotDeviceType.allCases.filter { $0.platform == .macOs }
        XCTAssertEqual(filtered, [.mac])
    }

    func testTvOSFilterYieldsAppleTVOnly() {
        let filtered = ScreenshotDeviceType.allCases.filter { $0.platform == .tvOs }
        XCTAssertEqual(filtered, [.appleTV])
    }

    func testVisionOSFilterYieldsVisionProOnly() {
        let filtered = ScreenshotDeviceType.allCases.filter { $0.platform == .visionOs }
        XCTAssertEqual(filtered, [.visionPro])
    }
}
