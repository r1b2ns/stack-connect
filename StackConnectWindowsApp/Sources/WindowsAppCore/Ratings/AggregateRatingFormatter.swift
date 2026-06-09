import Foundation

// T-W17 — Pure formatting helpers for `AggregateRating` display.
//
// Extracts the numeric formatting logic (average rating string + total count
// string) into a testable, Foundation-pure enum so TC-023 can verify the
// formatted output without requiring a UI harness.
//
// Both formatters are locale-aware:
// - The average uses one decimal place (e.g. "4.8" in en_US).
// - The total count uses a grouping separator (e.g. "42,308" in en_US).

/// Pure formatting helpers for `AggregateRating` display values.
public enum AggregateRatingFormatter {

    // MARK: - Cached Formatters

    /// One-decimal-place formatter for the average rating. Configured once,
    /// read-only afterwards — thread-safe for concurrent reads (BLOCKING-1).
    private static let averageFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    /// Grouping-separator formatter for the total count. `.decimal` style
    /// enables grouping by default (NIT-1: no explicit
    /// `usesGroupingSeparator` needed). Configured once (BLOCKING-1).
    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    // MARK: - Average Rating

    /// Formats the average rating to exactly one decimal place using the
    /// current locale's decimal separator.
    ///
    /// Example: `4.8` in en_US, `4,8` in de_DE.
    ///
    /// - Parameter averageRating: The weighted average (typically 0.0...5.0).
    /// - Returns: A locale-formatted string with one fractional digit.
    public static func formattedAverage(_ averageRating: Double) -> String {
        averageFormatter.string(from: NSNumber(value: averageRating))
            ?? String(format: "%.1f", averageRating)
    }

    // MARK: - Total Count

    /// Formats the total rating count with locale-aware grouping separators
    /// and appends the "ratings" label.
    ///
    /// Example: `"42,308 ratings"` in en_US, `"42.308 ratings"` in de_DE.
    ///
    /// - Parameter totalCount: The sum of ratings across all storefronts.
    /// - Returns: A formatted string like "42,308 ratings".
    public static func formattedTotalCount(_ totalCount: Int) -> String {
        let countString = countFormatter.string(from: NSNumber(value: totalCount))
            ?? "\(totalCount)"
        return "\(countString) ratings"
    }
}
