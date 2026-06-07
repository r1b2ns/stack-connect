import Foundation
import StackProtocols

/// Typed result produced by the In Review widget's `load()` (US-007 AC-2).
///
/// Foundation-pure (US-010): carries no SwiftUI. The platform view layers
/// render the apps list (or the "No apps in review" empty state) from this.
public struct InReviewWidgetData: Hashable, Sendable {
    /// Apps currently in the App Review pipeline, expanded per platform and
    /// sorted by recency (TC-033).
    public var apps: [AppModel]
    /// Accounts keyed by id, for resolving each app's owning account on tap.
    public var accountsMap: [String: AccountModel]

    public init(apps: [AppModel] = [], accountsMap: [String: AccountModel] = [:]) {
        self.apps = apps
        self.accountsMap = accountsMap
    }
}

/// Loads the data backing the "In Review" Home widget (US-007 AC-2 / TC-033).
///
/// Foundation-pure (US-010 AC-1/AC-5): no view code, no `makeView()`. Conforms
/// to the shared `HomeWidget` protocol and exposes its typed `data`; each
/// platform builds its own view over `data`.
@MainActor
public final class InReviewWidget: HomeWidget {

    public static let kind: HomeWidgetKind = .inReview

    public let configuration: HomeWidgetConfiguration

    /// The typed result of the most recent `load()`.
    public private(set) var data = InReviewWidgetData()
    public private(set) var isLoading: Bool = false

    private let storage: PersistentStorable

    public init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.configuration = configuration
        self.storage = storage
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = allApps.filter { !$0.isArchived }
            let inReview = AppStatusCategorizer.inReviewEntries(active)
            data = InReviewWidgetData(
                apps: inReview.sorted(by: HomeWidgetDataLoader.sortByRecency),
                accountsMap: await HomeWidgetDataLoader.loadAccounts(storage: storage)
            )
        } catch {
            HomeWidgetLog.error("[Widget][InReview] Failed to load apps: \(error.localizedDescription)")
            data = InReviewWidgetData()
        }
    }
}
