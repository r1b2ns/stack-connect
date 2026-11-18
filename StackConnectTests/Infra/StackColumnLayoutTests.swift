import XCTest
@testable import StackConnect

final class StackColumnLayoutTests: XCTestCase {

    func testNarrowDetailColumnUsesSingleColumn() {
        // iPad portrait, three columns with the sidebar open (~470pt).
        XCTAssertFalse(StackColumnLayout.fitsTwoColumns(width: 470))
    }

    func testJustBelowThresholdUsesSingleColumn() {
        XCTAssertFalse(StackColumnLayout.fitsTwoColumns(width: 639))
    }

    func testThresholdUsesTwoColumns() {
        XCTAssertTrue(StackColumnLayout.fitsTwoColumns(width: 640))
    }

    func testPortraitWithSidebarHiddenUsesTwoColumns() {
        // iPad Pro 13" portrait, sidebar hidden (~670pt detail column).
        XCTAssertTrue(StackColumnLayout.fitsTwoColumns(width: 670))
    }

    func testWideDetailColumnUsesTwoColumns() {
        // iPad landscape detail column (~1000pt).
        XCTAssertTrue(StackColumnLayout.fitsTwoColumns(width: 1000))
    }

    func testZeroWidthUsesSingleColumn() {
        XCTAssertFalse(StackColumnLayout.fitsTwoColumns(width: 0))
    }
}
