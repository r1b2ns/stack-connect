import WidgetKit
import SwiftUI
import StackCore

// The three widgets' layouts, given the family as a value so they can also be
// rendered outside WidgetKit (validation renders, see WidgetRenderingTests).

// MARK: - Row limits per family

func rowLimit(for family: WidgetFamily) -> Int {
    switch family {
    case .systemMedium: return 3
    default:            return 6
    }
}

/// Review rows: two lines each, so a few more fit than with the old layout.
func reviewRowLimit(for family: WidgetFamily) -> Int {
    switch family {
    case .systemMedium: return 2
    default:            return 5
    }
}

/// Header colors of prototype screen 20 (darker than the system tints so the
/// title reads on white).
enum WidgetTint {
    static let inReview = Color(red: 0.56, green: 0.30, blue: 0.0)
    static let awaiting = Color(red: 0.0, green: 0.35, blue: 0.72)
    static let reviews = Color(red: 0.42, green: 0.33, blue: 0.0)
}

// MARK: - App list (In Review, Awaiting Release)

struct WidgetAppListView: View {
    let family: WidgetFamily
    let title: String
    let tint: Color
    let rows: [WidgetDashboardRow]
    let totalCount: Int
    let emptyText: String
    let snapshot: WidgetSnapshot

    var body: some View {
        let shown = Array(rows.prefix(rowLimit(for: family)))
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            WidgetSectionHeader(title: title, tint: tint, count: totalCount)

            if shown.isEmpty {
                WidgetEmptyRow(icon: "checkmark.circle", text: emptyText)
            } else {
                ForEach(shown) { row in
                    WidgetRowLink(url: row.deepLink) {
                        WidgetAppRow(row: row, iconData: snapshot.iconData(for: row.iconUrl),
                                     iconSize: family == .systemLarge ? 36 : 28)
                    }
                }
                let remaining = totalCount - shown.count
                if remaining > 0 {
                    WidgetMoreRow(remaining: remaining)
                }
            }
            Spacer(minLength: 0)
            if family == .systemLarge, snapshot.dashboard.generatedAt > .distantPast {
                WidgetUpdatedFooter(date: snapshot.dashboard.generatedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Recent Reviews

struct RecentReviewsWidgetView: View {
    let family: WidgetFamily
    let snapshot: WidgetSnapshot

    var body: some View {
        let dashboard = snapshot.dashboard
        let reviews = Array(dashboard.recentReviews.prefix(reviewRowLimit(for: family)))
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            WidgetSectionHeader(title: String(localized: "Recent Reviews"), tint: WidgetTint.reviews) {
                HStack(spacing: 4) {
                    ForEach(dashboard.reviewPlatforms, id: \.self) { WidgetPlatformGlyph(platform: $0) }
                }
            }

            if reviews.isEmpty {
                WidgetEmptyRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "Reviews will appear after the next sync")
                )
            } else {
                ForEach(reviews) { review in
                    WidgetRowLink(url: review.deepLink) {
                        WidgetReviewRow(review: review, iconData: snapshot.iconData(for: review.iconUrl))
                    }
                }
            }
            Spacer(minLength: 0)
            if family == .systemLarge, dashboard.generatedAt > .distantPast {
                WidgetUpdatedFooter(date: dashboard.generatedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

