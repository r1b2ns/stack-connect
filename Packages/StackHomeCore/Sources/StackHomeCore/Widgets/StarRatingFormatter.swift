import Foundation

/// Foundation-pure star-rating formatting (US-007 / TC-042).
///
/// Produces a five-glyph string using filled (★, U+2605) and empty (☆, U+2606)
/// stars, clamped to the 0...5 range. Shared by both platforms: the Windows
/// widget renders this string directly, and it is available to iOS for any
/// text-based rating display. The iOS `HomeStarsView` renders the same logical
/// rating with SF Symbols over the clamped value.
public enum StarRatingFormatter {

    /// The number of filled stars for a rating, clamped to 0...5.
    public static func filledCount(for rating: Int) -> Int {
        min(max(rating, 0), 5)
    }

    /// A five-character "★★★☆☆"-style string for the given rating.
    public static func starString(
        for rating: Int,
        filled: Character = "\u{2605}",
        empty: Character = "\u{2606}"
    ) -> String {
        let filledCount = filledCount(for: rating)
        return String(repeating: filled, count: filledCount)
            + String(repeating: empty, count: 5 - filledCount)
    }
}
