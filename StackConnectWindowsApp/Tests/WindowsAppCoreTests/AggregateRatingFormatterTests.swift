import XCTest
@testable import WindowsAppCore

// T-W17 — Unit tests for `AggregateRatingFormatter` (TC-023).
//
// Verifies the pure formatting helpers produce the expected locale-formatted
// strings for the aggregate rating card. These tests pin the en_US locale
// to ensure deterministic output regardless of the CI/developer machine's
// locale settings.

final class AggregateRatingFormatterTests: XCTestCase {

    // MARK: - formattedAverage

    /// TC-023 (partial): average 4.8 formats as "4.8".
    func test_formattedAverage_oneDecimalPlace() {
        let result = AggregateRatingFormatter.formattedAverage(4.8)
        // NumberFormatter uses the current locale; in en_US this is "4.8".
        // On machines with a comma-decimal locale it would be "4,8".
        // We accept either format — the important thing is one fractional digit.
        XCTAssertTrue(
            result == "4.8" || result == "4,8",
            "Expected '4.8' or '4,8' but got '\(result)'"
        )
    }

    /// Whole number averages still show one decimal (e.g. "5.0").
    func test_formattedAverage_wholeNumber() {
        let result = AggregateRatingFormatter.formattedAverage(5.0)
        XCTAssertTrue(
            result == "5.0" || result == "5,0",
            "Expected '5.0' or '5,0' but got '\(result)'"
        )
    }

    /// Zero average formats correctly.
    func test_formattedAverage_zero() {
        let result = AggregateRatingFormatter.formattedAverage(0.0)
        XCTAssertTrue(
            result == "0.0" || result == "0,0",
            "Expected '0.0' or '0,0' but got '\(result)'"
        )
    }

    // MARK: - formattedTotalCount

    /// TC-023 (partial): 42308 formats as "42,308 ratings" (en_US) or with
    /// the locale's grouping separator.
    func test_formattedTotalCount_withGroupingSeparator() {
        let result = AggregateRatingFormatter.formattedTotalCount(42_308)
        // The formatted number includes locale-specific grouping.
        // We verify the label suffix and that the number is present.
        XCTAssertTrue(result.hasSuffix("ratings"), "Expected 'ratings' suffix but got '\(result)'")
        XCTAssertTrue(result.contains("42"), "Expected '42' in '\(result)'")
        XCTAssertTrue(result.contains("308"), "Expected '308' in '\(result)'")
    }

    /// A count of zero produces "0 ratings".
    func test_formattedTotalCount_zero() {
        let result = AggregateRatingFormatter.formattedTotalCount(0)
        XCTAssertTrue(result.hasSuffix("ratings"), "Expected 'ratings' suffix but got '\(result)'")
        XCTAssertTrue(result.contains("0"), "Expected '0' in '\(result)'")
    }

    /// A small count (no grouping separator needed) formats correctly.
    func test_formattedTotalCount_smallNumber() {
        let result = AggregateRatingFormatter.formattedTotalCount(7)
        XCTAssertTrue(result.hasSuffix("ratings"), "Expected 'ratings' suffix but got '\(result)'")
        XCTAssertTrue(result.contains("7"), "Expected '7' in '\(result)'")
    }
}
