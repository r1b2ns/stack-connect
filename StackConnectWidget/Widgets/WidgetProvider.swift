import WidgetKit
import Foundation

// MARK: - Deep Links

enum WidgetDeepLink {
    static let scheme = "stackconnect"

    static let home = URL(string: "\(scheme)://home")
    static let reviews = URL(string: "\(scheme)://reviews")
}

// MARK: - Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static let placeholder = WidgetEntry(date: .now, snapshot: .empty)
}

// MARK: - Provider
//
// Shared by all three widgets. Each timeline reload reads the current shared-store
// snapshot and asks the system to refresh again in ~30 minutes. The app also
// nudges `WidgetCenter` to reload immediately after a successful sync.

struct WidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        Task {
            let snapshot = await WidgetDataLoader.load()
            completion(WidgetEntry(date: .now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task {
            let snapshot = await WidgetDataLoader.load()
            let entry = WidgetEntry(date: .now, snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
                ?? Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}
