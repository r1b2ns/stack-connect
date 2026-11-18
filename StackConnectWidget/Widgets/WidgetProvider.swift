import WidgetKit
import Foundation
import StackCore

// MARK: - Deep Links

enum WidgetDeepLink {
    static let scheme = "stackconnect"

    static let home = URL(string: "\(scheme)://home?\(WidgetLinkSource.queryItem)")
    static let reviews = URL(string: "\(scheme)://reviews?\(WidgetLinkSource.queryItem)")
}

// MARK: - Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static let placeholder = WidgetEntry(date: .now, snapshot: .preview)
}

// MARK: - Provider
//
// Shared by all three widgets. Each timeline reload reads the dashboard snapshot
// the app wrote and asks the system to refresh again in ~30 minutes. The app
// also reloads the timelines right after writing a new snapshot.

struct WidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetDataLoader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: .now, snapshot: WidgetDataLoader.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Preview

extension WidgetSnapshot {
    /// Shown in the widget gallery: a mixed App Store / Google Play dashboard.
    static let preview = WidgetSnapshot(dashboard: WidgetDashboardSnapshot(
        generatedAt: .now,
        inReview: [
            WidgetDashboardRow(id: "1", name: "Pulse Timer", iconUrl: nil, platform: .iOS, statusText: "Waiting for Review",
                               statusColor: .orange, versionText: "3.1.0", progress: nil, deepLink: nil),
            WidgetDashboardRow(id: "2", name: "Trailhead", iconUrl: nil, platform: .android, statusText: "Open testing · In review",
                               statusColor: .orange, versionText: "4.3.0-beta", progress: nil, deepLink: nil)
        ],
        awaitingRelease: [
            WidgetDashboardRow(id: "3", name: "Ledger Pocket", iconUrl: nil, platform: .iOS, statusText: "Ready for Sale",
                               statusColor: .green, versionText: "2.8.1", progress: .phased(day: 3, total: 7, paused: false), deepLink: nil),
            WidgetDashboardRow(id: "4", name: "Trailhead", iconUrl: nil, platform: .android, statusText: "Production · Rolling out 20%",
                               statusColor: .blue, versionText: "4.2.0", progress: .rollout(fraction: 0.2, halted: false, asOf: nil), deepLink: nil)
        ],
        recentReviews: [
            WidgetDashboardReview(id: "r1", appName: "Trailhead", iconUrl: nil, platform: .android, rating: 2, title: nil,
                                  body: "Crashes when I open an offline map.", createdDate: .now.addingTimeInterval(-7200), hasResponse: false, deepLink: nil),
            WidgetDashboardReview(id: "r2", appName: "Pulse Timer", iconUrl: nil, platform: .iOS, rating: 5, title: "Exactly what I needed",
                                  body: "Simple, fast, and the widgets are great.", createdDate: .now.addingTimeInterval(-18000), hasResponse: true, deepLink: nil)
        ]
    ))
}
