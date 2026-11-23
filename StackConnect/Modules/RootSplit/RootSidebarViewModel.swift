import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol RootSidebarViewModelProtocol: ObservableObject {
    var uiState: RootSidebarUiState { get }
    /// Reloads the accounts and the release queue counts from storage.
    /// Returns `false` when the accounts could not be read.
    @discardableResult
    func load() async -> Bool
    /// The Refresh button / pull to refresh of a release queue column: reloads,
    /// then tracks a `refresh` action with its outcome on the queue's screen.
    func refresh(_ queue: RootReleaseQueue) async
    /// The loaded account with `id`, or `nil` when it is gone.
    func account(id: String) -> AccountModel?
    /// The Home widget backing a release queue (its rows fill the middle column).
    func widget(for queue: RootReleaseQueue) -> any HomeWidget
}

// MARK: - UiState

struct RootSidebarProviderSection: Identifiable, Equatable {
    let provider: ProviderType
    var accounts: [AccountModel]

    var id: ProviderType { provider }
}

struct RootSidebarUiState {
    /// One section per store, in sidebar order, accounts sorted by name.
    var providerSections: [RootSidebarProviderSection] = RootSidebarViewModel.visibleProviderOrder().map {
        RootSidebarProviderSection(provider: $0, accounts: [])
    }
    var queueCounts: [RootReleaseQueue: Int] = [:]
    var hasLoaded = false
}

// MARK: - Implementation

/// Data of the split view sidebar: the accounts of each store and the release
/// queue counters. Offline-first: everything comes from local storage; it
/// reloads when a sync finishes (`reloadTrigger`).
@MainActor
final class RootSidebarViewModel: RootSidebarViewModelProtocol {

    /// Store order of the sidebar (App Store Connect, Google Play, Firebase).
    nonisolated static let providerOrder: [ProviderType] = [.apple, .googlePlay, .firebase]

    /// `providerOrder` narrowed to the available stores: no Google Play
    /// section (nor its "Add Account") while `googlePlayAccounts` is OFF.
    nonisolated static func visibleProviderOrder(featureFlags: FeatureFlags = .shared) -> [ProviderType] {
        providerOrder.filter(featureFlags.isProviderAvailable)
    }

    @Published private(set) var uiState = RootSidebarUiState()

    private let storage: PersistentStorable
    private let queueWidgets: [RootReleaseQueue: any HomeWidget]
    private let queueCounter: (any HomeWidget) -> Int
    private let analytics: AnalyticsTracking
    private let featureFlags: FeatureFlags
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - reloadTrigger: emits when the stored data changed (default: every
    ///     finished sync).
    ///   - queueCounter: rows of a queue widget; injected for tests.
    init(
        storage: PersistentStorable? = nil,
        reloadTrigger: AnyPublisher<Void, Never>? = nil,
        queueCounter: ((any HomeWidget) -> Int)? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.storage = storage
        self.analytics = analytics
        self.featureFlags = featureFlags
        self.queueWidgets = Dictionary(uniqueKeysWithValues: RootReleaseQueue.allCases.map { queue in
            (queue, HomeWidgetRegistry.make(for: HomeWidgetConfiguration(kind: queue.widgetKind), storage: storage, featureFlags: featureFlags))
        })
        self.queueCounter = queueCounter ?? Self.entryCount

        (reloadTrigger ?? Self.syncFinished)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.load() }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func load() async -> Bool {
        let accounts: [AccountModel]
        var succeeded = true
        do {
            accounts = try await storage.fetchAll(AccountModel.self)
        } catch {
            Log.print.error("[RootSidebar] Failed to load accounts: \(error.localizedDescription)")
            accounts = []
            succeeded = false
        }
        uiState.providerSections = Self.sections(from: accounts, featureFlags: featureFlags)

        var counts: [RootReleaseQueue: Int] = [:]
        for (queue, widget) in queueWidgets {
            await widget.load()
            counts[queue] = queueCounter(widget)
        }
        uiState.queueCounts = counts
        uiState.hasLoaded = true
        return succeeded
    }

    func refresh(_ queue: RootReleaseQueue) async {
        let succeeded = await load()
        analytics.track(.action(.refresh, on: queue.analyticsScreen, result: succeeded ? .success : .failure))
    }

    func account(id: String) -> AccountModel? {
        uiState.providerSections.lazy.flatMap(\.accounts).first { $0.id == id }
    }

    func widget(for queue: RootReleaseQueue) -> any HomeWidget {
        // Every queue gets a widget in `init`.
        queueWidgets[queue] ?? HomeWidgetRegistry.make(
            for: HomeWidgetConfiguration(kind: queue.widgetKind),
            storage: storage,
            featureFlags: featureFlags
        )
    }

    // MARK: - Helpers

    /// One section per available store (hidden stores have no section and
    /// their accounts are left out, never deleted).
    static func sections(from accounts: [AccountModel], featureFlags: FeatureFlags = .shared) -> [RootSidebarProviderSection] {
        let normalized = featureFlags.visibleAccounts(accounts).map { account -> AccountModel in
            var account = account
            account.fillMissingRules()
            return account
        }
        return visibleProviderOrder(featureFlags: featureFlags).map { provider in
            RootSidebarProviderSection(
                provider: provider,
                accounts: normalized
                    .filter { $0.providerType == provider }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
    }

    private static func entryCount(_ widget: any HomeWidget) -> Int {
        switch widget {
        case let widget as InReviewWidget:        return widget.entries.count
        case let widget as AwaitingReleaseWidget: return widget.entries.count
        default:                                  return 0
        }
    }

    private static var syncFinished: AnyPublisher<Void, Never> {
        SyncService.shared.$state
            .map(\.lastSyncedAt)
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
