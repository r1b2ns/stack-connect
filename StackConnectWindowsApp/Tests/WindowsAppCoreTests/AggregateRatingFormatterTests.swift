import XCTest
@testable import WindowsAppCore

// T-W17 — Unit tests for `AggregateRatingFormatter` (TC-023).
//
// Verifies the pure formatting helpers produce structurally correct,
// locale-formatted strings for the aggregate rating card. Assertions are
// locale-independent: they split on the decimal separator set and check
// digit sequences rather than matching exact en_US strings (SHOULD-FIX-1).

final class AggregateRatingFormatterTests: XCTestCase {

    // MARK: - Helpers

    /// Known decimal separators across locales ("." for en_US, "," for de_DE).
    private static let decimalSeparators: CharacterSet = CharacterSet(charactersIn: ".,")

    /// Splits an average-formatted string on the locale's decimal separator
    /// and returns `(integerPart, fractionalPart)`, or `nil` if the format
    /// is unexpected.
    private func splitAverage(_ string: String) -> (integer: String, fraction: String)? {
        // Find exactly one separator character from the known set
        let separatorIndices = string.unicodeScalars.enumerated().filter {
            Self.decimalSeparators.contains($0.element)
        }
        guard separatorIndices.count == 1,
              let sepIdx = separatorIndices.first else {
            return nil
        }
        let charIndex = string.index(string.startIndex, offsetBy: sepIdx.offset)
        let integer = String(string[string.startIndex..<charIndex])
        let fraction = String(string[string.index(after: charIndex)...])
        return (integer, fraction)
    }

    /// Strips all non-digit characters from a string, returning only the
    /// raw digit sequence (e.g. "42,308 ratings" -> "42308").
    private func digitSequence(from string: String) -> String {
        string.filter(\.isNumber)
    }

    // MARK: - formattedAverage

    /// TC-023 (partial): average 4.8 formats with integer part "4" and
    /// exactly one fractional digit "8".
    func test_formattedAverage_oneDecimalPlace() {
        let result = AggregateRatingFormatter.formattedAverage(4.8)
        guard let parts = splitAverage(result) else {
            return XCTFail("Expected exactly one decimal separator in '\(result)'")
        }
        XCTAssertEqual(parts.integer, "4", "Integer part should be '4' in '\(result)'")
        XCTAssertEqual(parts.fraction.count, 1, "Fractional part should have exactly 1 digit in '\(result)'")
        XCTAssertEqual(parts.fraction, "8", "Fractional digit should be '8' in '\(result)'")
    }

    /// Whole number averages still show one decimal (e.g. "5.0").
    func test_formattedAverage_wholeNumber() {
        let result = AggregateRatingFormatter.formattedAverage(5.0)
        guard let parts = splitAverage(result) else {
            return XCTFail("Expected exactly one decimal separator in '\(result)'")
        }
        XCTAssertEqual(parts.integer, "5", "Integer part should be '5' in '\(result)'")
        XCTAssertEqual(parts.fraction.count, 1, "Fractional part should have exactly 1 digit in '\(result)'")
        XCTAssertEqual(parts.fraction, "0", "Fractional digit should be '0' in '\(result)'")
    }

    /// Zero average formats correctly (e.g. "0.0").
    func test_formattedAverage_zero() {
        let result = AggregateRatingFormatter.formattedAverage(0.0)
        guard let parts = splitAverage(result) else {
            return XCTFail("Expected exactly one decimal separator in '\(result)'")
        }
        XCTAssertEqual(parts.integer, "0", "Integer part should be '0' in '\(result)'")
        XCTAssertEqual(parts.fraction.count, 1, "Fractional part should have exactly 1 digit in '\(result)'")
        XCTAssertEqual(parts.fraction, "0", "Fractional digit should be '0' in '\(result)'")
    }

    // MARK: - formattedTotalCount

    /// TC-023 (partial): 42308 formats with digits "42308" in order,
    /// suffixed by " ratings".
    func test_formattedTotalCount_withGroupingSeparator() {
        let result = AggregateRatingFormatter.formattedTotalCount(42_308)
        XCTAssertTrue(result.hasSuffix(" ratings"), "Expected ' ratings' suffix but got '\(result)'")
        // Strip grouping separators and label — raw digits must match
        let digits = digitSequence(from: result)
        XCTAssertEqual(digits, "42308", "Digit sequence should be '42308' in '\(result)'")
    }

    /// A count of zero produces "0 ratings".
    func test_formattedTotalCount_zero() {
        let result = AggregateRatingFormatter.formattedTotalCount(0)
        XCTAssertTrue(result.hasSuffix(" ratings"), "Expected ' ratings' suffix but got '\(result)'")
        let digits = digitSequence(from: result)
        XCTAssertEqual(digits, "0", "Digit sequence should be '0' in '\(result)'")
    }

    /// A small count (no grouping separator needed) formats correctly.
    func test_formattedTotalCount_smallNumber() {
        let result = AggregateRatingFormatter.formattedTotalCount(7)
        XCTAssertTrue(result.hasSuffix(" ratings"), "Expected ' ratings' suffix but got '\(result)'")
        let digits = digitSequence(from: result)
        XCTAssertEqual(digits, "7", "Digit sequence should be '7' in '\(result)'")
    }
}
