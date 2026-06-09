import Foundation

// T-W18 — Pure formatting helper for review body excerpts.
//
// Extracts the truncation logic into a testable, Foundation-pure enum so
// TC-064 can verify boundary behaviour (short, exact, long, empty) without
// a UI harness. The formatter mirrors the style of `AggregateRatingFormatter`
// in the same directory.
//
// Truncation rules:
// - If the body (after whitespace trimming) is at most `maxLength` characters,
//   return it verbatim (no ellipsis).
// - If it exceeds `maxLength`, truncate to `maxLength` characters, then
//   back-track to the last word boundary (space/newline) to avoid mid-word
//   breaks, and append "...". If no word boundary is found within the
//   truncated range (single giant word), truncate at `maxLength` directly.
// - Empty or nil bodies produce an empty string.
//
// Character counting uses Swift's `Character`-based `String.count` (grapheme
// clusters), NOT UTF-16 code units, so emoji and CJK characters are counted
// correctly (TC-065 unicode safety).

/// Pure formatting helpers for review body excerpt display.
public enum ReviewExcerptFormatter {

    /// The default maximum character count for body excerpts in the list
    /// variant. The home (compact) variant may use a smaller limit.
    public static let defaultMaxLength = 100

    /// Produces a truncated excerpt of a review body.
    ///
    /// - Parameters:
    ///   - body: The full review body text. `nil` or empty returns `""`.
    ///   - maxLength: The maximum number of `Character`s before truncation.
    ///     Defaults to ``defaultMaxLength`` (100).
    /// - Returns: The body verbatim if it fits, or a word-boundary-truncated
    ///   excerpt followed by "\u{2026}" (ellipsis).
    public static func excerpt(
        _ body: String?,
        maxLength: Int = defaultMaxLength
    ) -> String {
        guard let body, !body.isEmpty else { return "" }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Fits within the limit — return verbatim.
        guard trimmed.count > maxLength else { return trimmed }

        // Truncate to maxLength characters (Character-based, unicode-safe).
        let truncationIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        let prefix = trimmed[trimmed.startIndex..<truncationIndex]

        // Back-track to the last word boundary to avoid mid-word breaks.
        if let lastSpace = prefix.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return String(prefix[prefix.startIndex..<lastSpace]) + "\u{2026}"
        }

        // No word boundary found (single long word / CJK text) — hard truncate.
        return String(prefix) + "\u{2026}"
    }
}
