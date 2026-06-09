import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W17 — Aggregate rating card for the Ratings & Reviews screen (design
// spec section 2.4/2.5, AC-W10-1).
//
// A stateless, input-driven leaf component that displays:
// - The numeric average rating (one decimal place, locale-aware)
// - A five-star Unicode rating via `WindowsRatingStarsView` (Int-based;
//   the fractional part is conveyed by the numeric display)
// - The locale-formatted total count with grouping separators + label
//
// Wrapped in the standard widget card chrome (`windowsWidgetCard()`) so it
// matches sibling cards on the Home and detail screens.
//
// Number formatting is delegated to `AggregateRatingFormatter` in
// `WindowsAppCore`, which is unit-tested (TC-023).
//
// When `totalCount == 0` (the zero-rating fallback from `ITunesLookupService`),
// the card renders a neutral "No ratings yet" placeholder instead of misleading
// "0 ratings" + empty stars (SHOULD-FIX-2).

struct WindowsAggregateRatingCard: View {
    let rating: AggregateRating

    var body: some View {
        buildContent()
            .windowsWidgetCard()
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if rating.totalCount == 0 {
            // Empty state: no rating data available (SHOULD-FIX-2)
            Text("No ratings yet")
                .foregroundColor(.gray)
        } else {
            VStack(spacing: 4) {
                // Numeric average — prominent display
                Text(AggregateRatingFormatter.formattedAverage(rating.averageRating))
                    .fontWeight(.bold)

                // Star glyphs (integer-based; half-stars not supported)
                WindowsRatingStarsView(rating: Int(rating.averageRating.rounded()))

                // Total count with label
                Text(AggregateRatingFormatter.formattedTotalCount(rating.totalCount))
                    .foregroundColor(.gray)
            }
        }
    }
}
