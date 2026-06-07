import XCTest
@testable import StackHomeCore

/// Covers the pure star-rating formatting moved into core (TC-042).
final class StarRatingFormatterTests: XCTestCase {

    func testStarStringForEachRating() {
        XCTAssertEqual(StarRatingFormatter.starString(for: 0), "\u{2606}\u{2606}\u{2606}\u{2606}\u{2606}")
        XCTAssertEqual(StarRatingFormatter.starString(for: 1), "\u{2605}\u{2606}\u{2606}\u{2606}\u{2606}")
        XCTAssertEqual(StarRatingFormatter.starString(for: 3), "\u{2605}\u{2605}\u{2605}\u{2606}\u{2606}")
        XCTAssertEqual(StarRatingFormatter.starString(for: 5), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
    }

    func testStarStringClampsOutOfRangeRatings() {
        XCTAssertEqual(StarRatingFormatter.starString(for: -2), "\u{2606}\u{2606}\u{2606}\u{2606}\u{2606}")
        XCTAssertEqual(StarRatingFormatter.starString(for: 9), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
    }

    func testStarStringAlwaysFiveGlyphs() {
        for rating in -3...8 {
            XCTAssertEqual(StarRatingFormatter.starString(for: rating).count, 5)
        }
    }

    func testFilledCountClamps() {
        XCTAssertEqual(StarRatingFormatter.filledCount(for: -1), 0)
        XCTAssertEqual(StarRatingFormatter.filledCount(for: 4), 4)
        XCTAssertEqual(StarRatingFormatter.filledCount(for: 12), 5)
    }
}
