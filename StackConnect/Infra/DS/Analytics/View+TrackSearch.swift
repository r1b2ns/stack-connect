import SwiftUI
import StackProtocols

/// One search session of a `.searchable` list: it starts when the query
/// becomes non-empty and ends when it is cleared again. `commit` returns the
/// `search` event at most once per session — after the typing settled, on
/// submit, or when the screen goes away — with the result count bucketed.
///
/// The query itself never leaves this type: only whether it is empty.
@MainActor
final class SearchAnalyticsSession {

    private(set) var isActive = false
    private(set) var hasReported = false
    private(set) var latestResultCount = 0

    /// The query changed. An empty query ends the session.
    func queryChanged(_ query: String) {
        let isEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            isActive = false
            hasReported = false
        } else {
            isActive = true
        }
    }

    func resultCountChanged(_ count: Int) {
        latestResultCount = count
    }

    /// The `search` action of this session, the first time only.
    func commit(on screen: AnalyticsScreen) -> AnalyticsEvent? {
        guard isActive, !hasReported else { return nil }
        hasReported = true
        return .action(
            .search,
            on: screen,
            parameters: [AnalyticsParameterKey.resultCountBucket: .string(AnalyticsCountBucket(count: latestResultCount).rawValue)]
        )
    }
}

/// Tracks searches of a `.searchable` list (see `SearchAnalyticsSession`).
struct StackTrackSearchModifier: ViewModifier {

    /// How long the query must stay unchanged to count as a search.
    static let settleDelay: Duration = .milliseconds(1500)

    let query: String
    let resultCount: Int
    let screen: AnalyticsScreen

    @Environment(\.analytics) private var analytics
    @State private var session = SearchAnalyticsSession()

    func body(content: Content) -> some View {
        content
            .onChange(of: resultCount, initial: true) { _, count in
                session.resultCountChanged(count)
            }
            .onChange(of: query, initial: true) { _, newQuery in
                session.queryChanged(newQuery)
            }
            .task(id: query) {
                guard session.isActive else { return }
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                commit()
            }
            .onSubmit(of: .search) { commit() }
            .onDisappear { commit() }
    }

    private func commit() {
        if let event = session.commit(on: screen) {
            analytics.track(event)
        }
    }
}

extension View {
    /// Tracks a `search` action once per search session on `screen`, with the
    /// bucketed `resultCount` — never the query. Apply next to `.searchable`.
    func trackSearch(query: String, resultCount: Int, on screen: AnalyticsScreen) -> some View {
        modifier(StackTrackSearchModifier(query: query, resultCount: resultCount, screen: screen))
    }
}
