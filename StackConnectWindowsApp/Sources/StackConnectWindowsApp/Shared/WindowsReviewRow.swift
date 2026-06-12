import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W18 — Reusable review-row component for the Ratings & Reviews list
// (T-W19) and the Recent Reviews home widget (T-W28).
//
// Renders a single `CustomerReviewModel` with:
//   - Rating stars (via shared `WindowsRatingStarsView`)
//   - Date formatted as "d MMM yyyy" (via `WindowsDateFormatting.absoluteDate`)
//   - Bold title
//   - 2-3 line body excerpt (via `ReviewExcerptFormatter` in WindowsAppCore)
//   - Nickname preceded by a person glyph (U+1F464)
//   - Trailing chevron ">"
//
// Supports two variants via `WindowsReviewRowVariant`:
//   - `.list`:  Full-size row for the Ratings & Reviews list screen (T-W19).
//               Uses the default 100-char excerpt limit, standard padding.
//   - `.home`:  Compact row for the Recent Reviews home widget (T-W28).
//               Uses a shorter 60-char excerpt limit, tighter spacing.
//
// Tapping the row invokes `onTap`, carrying the review so the consumer can
// navigate to Review Detail (AC-W11-6). The actual route wiring belongs to
// T-W19/T-W21 — this component only exposes the callback.

// MARK: - Variant

/// Controls the visual density of a `WindowsReviewRow`.
enum WindowsReviewRowVariant {
    /// Full-size row for the Ratings & Reviews list (T-W19).
    case list
    /// Compact row for the Recent Reviews home widget (T-W28).
    case home

    /// The maximum character count for the body excerpt in this variant.
    var excerptMaxLength: Int {
        switch self {
        case .list: return ReviewExcerptFormatter.defaultMaxLength  // 100
        case .home: return 60
        }
    }

    /// Outer padding for the row card.
    var padding: Int {
        switch self {
        case .list: return 12
        case .home: return 8
        }
    }

    /// Vertical spacing between content elements.
    var verticalSpacing: Int {
        switch self {
        case .list: return 4
        case .home: return 2
        }
    }
}

// MARK: - Row View

struct WindowsReviewRow: View {
    let review: CustomerReviewModel
    let variant: WindowsReviewRowVariant
    let onTap: (CustomerReviewModel) -> Void

    var body: some View {
        HStack(spacing: 12) {
            buildContent()

            // Trailing disclosure chevron (AC-W11-1)
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(variant.padding)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        // Stroke MUST live in `.background` (not `.overlay`): on the AppKit
        // backend an overlaid stroke becomes a sibling path view on top of the
        // row that swallows clicks, blocking the .onTapGesture. Behind the
        // translucent fill the border still shows through.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
        .onTapGesture {
            onTap(review)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        VStack(spacing: variant.verticalSpacing) {
            // Row 1: Stars + Date
            buildHeaderRow()

            // Row 2: Bold title (if present)
            if let title = review.title, !title.isEmpty {
                HStack {
                    Text(title)
                        .fontWeight(.bold)
                    Spacer()
                }
            }

            // Row 3: Body excerpt (2-3 lines)
            buildBodyExcerpt()

            // Row 4: Nickname with person glyph
            buildNicknameRow()
        }
    }

    /// Stars on the left, date on the right.
    @ViewBuilder
    private func buildHeaderRow() -> some View {
        HStack(spacing: 6) {
            // Rating stars (AC-W11-1) via shared T-W04 component
            WindowsRatingStarsView(rating: review.rating)

            Spacer()

            // Absolute date formatted as "d MMM yyyy" (AC-W11-1)
            if let date = review.createdDate {
                Text(WindowsDateFormatting.absoluteDate(date))
                    .foregroundColor(.gray)
            }
        }
    }

    /// Body excerpt truncated per variant's maxLength.
    @ViewBuilder
    private func buildBodyExcerpt() -> some View {
        let excerpt = ReviewExcerptFormatter.excerpt(
            review.body,
            maxLength: variant.excerptMaxLength
        )
        if !excerpt.isEmpty {
            HStack {
                Text(excerpt)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }

    /// Person glyph + reviewer nickname.
    @ViewBuilder
    private func buildNicknameRow() -> some View {
        if let nickname = review.reviewerNickname, !nickname.isEmpty {
            HStack(spacing: 4) {
                // Person glyph (U+1F464 — "bust in silhouette")
                Text("\u{1F464}")
                Text(nickname)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }
}
