import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C2 — the "Recent Reviews" Home widget view (US-007 AC-4,
// design §2.5). Windows counterpart of the iOS `RecentReviewsWidgetView` in
// `HomeWidgetViewFactory.swift`: same data (`RecentReviewsWidget.data`,
// `RecentReviewsWidgetData`, capped at 5 by the core's `load()`), different UI
// framework.
//
// Renders, inside its own radius-8 card:
//   • header: 💬 glyph + bold "Recent Reviews" + "(count)" + Spacer.
//   • while loading → "Loading…" row (AC-5).
//   • no reviews    → "Reviews will appear after the next sync" row.
//   • reviews       → one tappable row per review (app name + ★/☆ rating string +
//                     title + 2-line excerpt + relative date), tapping pushes
//                     `.reviewDetail` (AC-6); followed by a "See more >" text
//                     button that pushes `.allReviews` (AC-7).
//
// The 5-cap is enforced by the core (`RecentReviewsWidget.maxReviews`); the view
// renders whatever the data carries. Star glyphs come from the shared core
// `StarRatingFormatter.starString` (TC-042) — no rating logic is reimplemented
// here. App icons are gray placeholders (D4 — no AsyncImage / image fetch).

struct WindowsRecentReviewsWidgetView: View {

    /// The Recent Reviews widget's typed result data from the shared core
    /// (already capped at 5).
    let data: RecentReviewsWidgetData
    /// Whether the widget's `load()` is in flight (AC-5).
    let isLoading: Bool
    /// Pushes the Review Detail route on tap (AC-6 — v1 placeholder).
    let onSelectReview: (HomeRecentReview) -> Void
    /// Pushes the Ratings & Reviews route from "See more" (AC-7, design §2.3).
    /// Receives the first review's app context so the caller can route to the
    /// correct app's ratings screen; `nil` when the widget is empty.
    let onSeeMore: (AppModel?) -> Void

    var body: some View {
        VStack(spacing: 12) {
            WindowsWidgetHeaderView(
                glyph: HomeWidgetKind.recentReviews.windowsGlyph,
                title: "Recent Reviews",
                count: data.reviews.count
            )

            if isLoading {
                WindowsWidgetLoadingRow()
            } else if data.reviews.isEmpty {
                WindowsWidgetEmptyRow(text: "Reviews will appear after the next sync")
            } else {
                ForEach(data.reviews, id: \.id) { item in
                    reviewRow(item)
                        .onTapGesture { onSelectReview(item) }
                }

                // "See more >" text button → All Reviews (AC-7, design §2.5).
                HStack(spacing: 4) {
                    Text("See more")
                        .foregroundColor(.blue)
                    Text(">")
                        .foregroundColor(.blue)
                    Spacer()
                }
                .onTapGesture { onSeeMore(data.reviews.first?.app) }
            }
        }
        .windowsWidgetCard()
    }

    /// A single review row: a 36×36 gray placeholder icon (D4) on the left, then
    /// the app name, the ★/☆ rating string, the relative date, the title, and a
    /// 2-line body excerpt.
    private func reviewRow(_ item: HomeRecentReview) -> some View {
        HStack(spacing: 12) {
            WindowsWidgetPlaceholderIcon()

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.app.name)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                    // Shared core formatter (TC-042): ★ for filled, ☆ for empty.
                    Text(StarRatingFormatter.starString(for: item.review.rating))
                        .foregroundColor(.yellow)
                    Spacer()
                    if let date = item.review.createdDate {
                        Text(Self.relativeDate(date))
                            .foregroundColor(.gray)
                    }
                }

                if let title = item.review.title, !title.isEmpty {
                    HStack {
                        Text(title)
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                if let body = item.review.body, !body.isEmpty {
                    HStack {
                        Text(body)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Relative date

    /// Returns a short relative date string (e.g. "2h ago").
    /// `RelativeDateTimeFormatter` is Apple-only; the Windows/Linux build uses a
    /// manual fallback so no Darwin API leaks into swift-corelibs-foundation.
    private static func relativeDate(_ date: Date) -> String {
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
        #else
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:      return "just now"
        case ..<3_600:   return "\(seconds / 60)m ago"
        case ..<86_400:  return "\(seconds / 3_600)h ago"
        case ..<604_800: return "\(seconds / 86_400)d ago"
        default:         return "\(seconds / 604_800)w ago"
        }
        #endif
    }
}
