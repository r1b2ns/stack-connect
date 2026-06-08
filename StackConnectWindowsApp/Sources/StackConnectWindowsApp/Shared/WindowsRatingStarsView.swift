import SwiftCrossUI
import StackHomeCore

// T-W04 — Star rating display using Unicode stars (design spec section 2.4).
//
// Renders a five-star rating using filled (★) and empty (☆) Unicode glyphs.
// Delegates to the existing `StarRatingFormatter` in `StackHomeCore` for the
// rating math (clamping, glyph string generation) — no rating logic is
// duplicated here.
//
// The rating is an `Int` (matching the review model); half-star rendering is
// not supported since the source data is integer-based.

struct WindowsRatingStarsView: View {
    let rating: Int

    var body: some View {
        Text(StarRatingFormatter.starString(for: rating))
            .foregroundColor(.yellow)
    }
}
