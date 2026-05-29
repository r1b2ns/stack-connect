import WidgetKit
import SwiftUI

// MARK: - Row limits per family

private func rowLimit(for family: WidgetFamily) -> Int {
    switch family {
    case .systemMedium: return 3
    case .systemLarge:  return 6
    default:            return 6
    }
}

/// Review rows are taller (app name + stars + date, title and body), so fewer
/// fit per family than the compact app rows.
private func reviewRowLimit(for family: WidgetFamily) -> Int {
    switch family {
    case .systemMedium: return 2
    case .systemLarge:  return 4
    default:            return 4
    }
}

// MARK: - In Review

struct InReviewWidget: Widget {
    let kind = "StackConnectInReviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            InReviewWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "In Review"))
        .description(String(localized: "Apps currently in App Store review."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct InReviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        let apps = Array(entry.snapshot.inReview.prefix(rowLimit(for: family)))
        VStack(alignment: .leading, spacing: 8) {
            WidgetSectionHeader(
                icon: "magnifyingglass.circle.fill",
                title: String(localized: "In Review"),
                count: entry.snapshot.inReview.count,
                tint: .orange
            )

            if apps.isEmpty {
                WidgetEmptyRow(icon: "checkmark.circle", text: String(localized: "No apps in review"))
                Spacer(minLength: 0)
            } else {
                ForEach(apps) { app in
                    WidgetAppRow(app: app)
                }
                let remaining = entry.snapshot.inReview.count - apps.count
                if remaining > 0 {
                    WidgetMoreRow(remaining: remaining)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.home)
    }
}

// MARK: - Awaiting Release

struct AwaitingReleaseWidget: Widget {
    let kind = "StackConnectAwaitingReleaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            AwaitingReleaseWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "Awaiting Release"))
        .description(String(localized: "Apps approved and awaiting release."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct AwaitingReleaseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        let apps = Array(entry.snapshot.awaitingRelease.prefix(rowLimit(for: family)))
        VStack(alignment: .leading, spacing: 8) {
            WidgetSectionHeader(
                icon: "paperplane.circle.fill",
                title: String(localized: "Awaiting Release"),
                count: entry.snapshot.awaitingRelease.count,
                tint: .blue
            )

            if apps.isEmpty {
                WidgetEmptyRow(icon: "checkmark.circle", text: String(localized: "Nothing awaiting release"))
                Spacer(minLength: 0)
            } else {
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetAppRow(app: app)
                        if let phased = entry.snapshot.phasedByAppId[app.id],
                           phased.state == "ACTIVE" || phased.state == "PAUSED",
                           let day = phased.currentDayNumber {
                            WidgetPhasedProgress(day: day, total: 7, paused: phased.state == "PAUSED")
                                .padding(.leading, 38)
                        }
                    }
                }
                let remaining = entry.snapshot.awaitingRelease.count - apps.count
                if remaining > 0 {
                    WidgetMoreRow(remaining: remaining)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.home)
    }
}

// MARK: - Recent Reviews

struct RecentReviewsWidget: Widget {
    let kind = "StackConnectRecentReviewsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            RecentReviewsWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "Recent Reviews"))
        .description(String(localized: "Latest customer reviews across your apps."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct RecentReviewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        let reviews = Array(entry.snapshot.recentReviews.prefix(reviewRowLimit(for: family)))
        VStack(alignment: .leading, spacing: 8) {
            WidgetSectionHeader(
                icon: "star.bubble.fill",
                title: String(localized: "Recent Reviews"),
                count: entry.snapshot.recentReviews.count,
                tint: .yellow
            )

            if reviews.isEmpty {
                WidgetEmptyRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "Reviews will appear after the next sync")
                )
                Spacer(minLength: 0)
            } else {
                ForEach(Array(reviews.enumerated()), id: \.element.id) { index, item in
                    WidgetReviewRow(item: item)
                    if index < reviews.count - 1 {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetDeepLink.reviews)
    }
}

// MARK: - Bundle

@main
struct StackConnectWidgetBundle: WidgetBundle {
    var body: some Widget {
        InReviewWidget()
        AwaitingReleaseWidget()
        RecentReviewsWidget()
    }
}
