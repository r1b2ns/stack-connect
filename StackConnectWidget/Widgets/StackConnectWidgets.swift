import WidgetKit
import SwiftUI
import StackCore

// MARK: - In Review

struct InReviewWidget: Widget {
    let kind = "StackConnectInReviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            WidgetFamilyReader { family in
                WidgetAppListView(
                    family: family,
                    title: String(localized: "In Review"),
                    tint: WidgetTint.inReview,
                    rows: entry.snapshot.dashboard.inReview,
                    totalCount: entry.snapshot.dashboard.inReviewCount,
                    emptyText: String(localized: "No apps in review"),
                    snapshot: entry.snapshot
                )
            }
            .widgetURL(WidgetDeepLink.home)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "In Review"))
        .description(SharedFeatureFlags.isGooglePlayAccountsEnabled()
            ? String(localized: "Apps waiting on App Store or Google Play review.")
            : String(localized: "Apps waiting on App Store review."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Awaiting Release

struct AwaitingReleaseWidget: Widget {
    let kind = "StackConnectAwaitingReleaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            WidgetFamilyReader { family in
                WidgetAppListView(
                    family: family,
                    title: String(localized: "Awaiting Release"),
                    tint: WidgetTint.awaiting,
                    rows: entry.snapshot.dashboard.awaitingRelease,
                    totalCount: entry.snapshot.dashboard.awaitingReleaseCount,
                    emptyText: String(localized: "Nothing awaiting release"),
                    snapshot: entry.snapshot
                )
            }
            .widgetURL(WidgetDeepLink.home)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "Awaiting Release"))
        .description(String(localized: "Approved releases and staged rollouts."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Recent Reviews

struct RecentReviewsWidget: Widget {
    let kind = "StackConnectRecentReviewsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            WidgetFamilyReader { family in
                RecentReviewsWidgetView(family: family, snapshot: entry.snapshot)
            }
            .widgetURL(WidgetDeepLink.reviews)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(String(localized: "Recent Reviews"))
        .description(String(localized: "Latest customer reviews across your apps."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Hands the environment's widget family to views that take it as a value (so
/// they can also be rendered outside WidgetKit).
private struct WidgetFamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder var content: (WidgetFamily) -> Content

    var body: some View {
        content(family)
    }
}

// MARK: - Previews

#Preview("In Review", as: .systemMedium) {
    InReviewWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Awaiting Release", as: .systemLarge) {
    AwaitingReleaseWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .preview)
}

#Preview("Recent Reviews", as: .systemMedium) {
    RecentReviewsWidget()
} timeline: {
    WidgetEntry(date: .now, snapshot: .preview)
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
