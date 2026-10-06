import Foundation

/// Parses the raw ISO8601 timestamps the Rust core passes through unchanged.
///
/// Store timestamps may or may not include fractional seconds (e.g.
/// `2024-01-15T10:30:00Z` vs `2024-01-15T10:30:00.123Z`). A single
/// `ISO8601DateFormatter` cannot tolerate both, so this tries with fractional
/// seconds first, then falls back to the plain internet date-time format.
enum ISO8601DateParser {

    static func date(from string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
