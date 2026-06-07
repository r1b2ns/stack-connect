import Foundation
import StackProtocols

/// Typed result produced by the Awaiting Release widget's `load()` (US-007 AC-3).
///
/// Foundation-pure (US-010): no SwiftUI. Carries the awaiting-release apps plus
/// the phased-release records keyed by app id so the view can render the
/// optional "Day N of 7" / paused indicator (TC-034).
public struct AwaitingReleaseWidgetData: Hashable, Sendable {
    /// Apps approved and awaiting release, sorted by recency.
    public var apps: [AppModel]
    /// Phased-release records keyed by app id (drives "Day N of 7").
    public var phasedByAppId: [String: PhasedReleaseModel]
    /// Accounts keyed by id, for resolving each app's owning account on tap.
    public var accountsMap: [String: AccountModel]

    public init(
        apps: [AppModel] = [],
        phasedByAppId: [String: PhasedReleaseModel] = [:],
        accountsMap: [String: AccountModel] = [:]
    ) {
        self.apps = apps
        self.phasedByAppId = phasedByAppId
        self.accountsMap = accountsMap
    }
}

/// Loads the data backing the "Awaiting Release" Home widget (US-007 AC-3 /
/// TC-034). Groups by phased-release state via `AppStatusCategorizer`.
///
/// Foundation-pure (US-010 AC-1/AC-5): no view code, no `makeView()`.
@MainActor
public final class AwaitingReleaseWidget: HomeWidget {

    public static let kind: HomeWidgetKind = .awaitingRelease

    public let configuration: HomeWidgetConfiguration

    public private(set) var data = AwaitingReleaseWidgetData()
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
            let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            let (_, awaiting) = AppStatusCategorizer.categorize(active, phasedByAppId: phased)
            data = AwaitingReleaseWidgetData(
                apps: awaiting.sorted(by: HomeWidgetDataLoader.sortByRecency),
                phasedByAppId: phased,
                accountsMap: await HomeWidgetDataLoader.loadAccounts(storage: storage)
            )
        } catch {
            HomeWidgetLog.error("[Widget][AwaitingRelease] Failed to load apps: \(error.localizedDescription)")
            data = AwaitingReleaseWidgetData()
        }
    }
}
