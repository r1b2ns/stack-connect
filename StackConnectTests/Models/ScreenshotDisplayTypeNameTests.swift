import XCTest
@testable import StackConnect

/// Labels for ASC screenshot display types / app preview types. Expectations are
/// resolved through the same string catalog so the suite passes in any simulator
/// language (e.g. pt-BR "iPhone (tela de 6,7\")").
final class ScreenshotDisplayTypeNameTests: XCTestCase {

    private func name(_ raw: String?) -> String {
        ScreenshotDisplayTypeName.displayName(for: raw)
    }

    /// Localized `<product> <size>" Display` for the current language/locale.
    private func display(_ product: String, _ inches: Double) -> String {
        let size = inches.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(product) \(size)\" Display")
    }

    private func iMessage(_ name: String) -> String {
        String(localized: "\(name) (iMessage)")
    }

    private var ipadPro2ndGen: String { String(localized: "iPad Pro (2nd generation)") }

    func testIPhoneDisplayTypesUseInchLabels() {
        XCTAssertEqual(name("APP_IPHONE_67"), display("iPhone", 6.7))
        XCTAssertEqual(name("APP_IPHONE_65"), display("iPhone", 6.5))
        XCTAssertEqual(name("APP_IPHONE_61"), display("iPhone", 6.1))
        XCTAssertEqual(name("APP_IPHONE_58"), display("iPhone", 5.8))
        XCTAssertEqual(name("APP_IPHONE_55"), display("iPhone", 5.5))
        XCTAssertEqual(name("APP_IPHONE_47"), display("iPhone", 4.7))
        XCTAssertEqual(name("APP_IPHONE_40"), display("iPhone", 4))
        XCTAssertEqual(name("APP_IPHONE_35"), display("iPhone", 3.5))
    }

    func testIPadDisplayTypes() {
        XCTAssertEqual(name("APP_IPAD_PRO_3GEN_129"), display("iPad Pro", 12.9))
        XCTAssertEqual(name("APP_IPAD_PRO_3GEN_11"), display("iPad Pro", 11))
        XCTAssertEqual(name("APP_IPAD_PRO_129"), display(ipadPro2ndGen, 12.9))
        XCTAssertEqual(name("APP_IPAD_105"), display("iPad", 10.5))
        XCTAssertEqual(name("APP_IPAD_97"), display("iPad", 9.7))
    }

    func testOtherPlatformDisplayTypes() {
        XCTAssertEqual(name("APP_DESKTOP"), "Mac")
        XCTAssertEqual(name("APP_APPLE_TV"), "Apple TV")
        XCTAssertEqual(name("APP_APPLE_VISION_PRO"), "Apple Vision Pro")
        XCTAssertEqual(name("APP_WATCH_ULTRA"), "Apple Watch Ultra")
        XCTAssertEqual(name("APP_WATCH_SERIES_10"), "Apple Watch Series 10")
        XCTAssertEqual(name("APP_WATCH_SERIES_7"), "Apple Watch Series 7")
        XCTAssertEqual(name("APP_WATCH_SERIES_4"), "Apple Watch Series 4")
        XCTAssertEqual(name("APP_WATCH_SERIES_3"), "Apple Watch Series 3")
    }

    func testIMessageDisplayTypesAreSuffixed() {
        XCTAssertEqual(name("IMESSAGE_APP_IPHONE_67"), iMessage(display("iPhone", 6.7)))
        XCTAssertEqual(name("IMESSAGE_APP_IPAD_PRO_3GEN_11"), iMessage(display("iPad Pro", 11)))
    }

    func testAppPreviewTypesShareTheMapping() {
        XCTAssertEqual(name("IPHONE_67"), display("iPhone", 6.7))
        XCTAssertEqual(name("IPAD_PRO_3GEN_129"), display("iPad Pro", 12.9))
        XCTAssertEqual(name("DESKTOP"), "Mac")
        XCTAssertEqual(name("APPLE_VISION_PRO"), "Apple Vision Pro")
    }

    func testUnknownTypesAreHumanizedWithProductCasing() {
        XCTAssertEqual(name("APP_IPHONE_69"), "iPhone 69")
        XCTAssertEqual(name("APP_IPAD_PRO_M4"), "iPad Pro M4")
    }

    func testNilOrEmptyIsUnknown() {
        XCTAssertEqual(name(nil), String(localized: "Unknown"))
        XCTAssertEqual(name(""), String(localized: "Unknown"))
    }

    func testScreenshotSetModelUsesTheMapping() {
        XCTAssertEqual(ScreenshotSetModel(id: "s", displayType: "APP_IPHONE_67").displayName, display("iPhone", 6.7))
    }

    func testNeverFallsBackToMechanicalTitleCase() {
        XCTAssertNotEqual(name("APP_IPHONE_67"), "Iphone 67")
        XCTAssertTrue(name("APP_IPHONE_67").hasPrefix("iPhone"))
        XCTAssertTrue(name("APP_IPAD_97").contains("iPad"))
    }
}
