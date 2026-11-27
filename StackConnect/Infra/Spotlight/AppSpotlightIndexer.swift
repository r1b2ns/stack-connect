import Combine
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

// MARK: - Entry

/// One app as Spotlight shows it: its name, found by name or bundle id, and
/// opened through its `stackconnect://app/{accountId}/{appId}` deep link (the
/// item's unique identifier). Grouped by account (the domain identifier).
struct AppSpotlightEntry: Equatable, Sendable {
    let url: URL
    let accountId: String
    let name: String
    /// The bundle id (App Store Connect) or package name (Google Play).
    let bundleId: String
}

// MARK: - Index Writing

/// The on-device Spotlight index, behind a seam so the indexer is testable.
protocol AppSpotlightIndexWriting: Sendable {
    /// Replaces every item this app indexed with `entries`.
    func replaceAll(with entries: [AppSpotlightEntry]) async throws
}

/// `CSSearchableIndex.default()`. The app indexes nothing else there, so a
/// rebuild starts from an empty index.
struct CoreSpotlightIndexWriter: AppSpotlightIndexWriting {
    func replaceAll(with entries: [AppSpotlightEntry]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteAllSearchableItems()
        guard !entries.isEmpty else { return }
        try await index.indexSearchableItems(entries.map(Self.item))
    }

    private static func item(for entry: AppSpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.name
        attributes.displayName = entry.name
        attributes.contentDescription = entry.bundleId
        attributes.keywords = [entry.bundleId]
        return CSSearchableItem(
            uniqueIdentifier: entry.url.absoluteString,
            domainIdentifier: entry.accountId,
            attributeSet: attributes
        )
    }
}

// MARK: - Indexer

/// Keeps the user's apps in Spotlight, so searching an app name opens it in
/// StackConnect (`AppSpotlightIndexer.deepLinkURL(from:)`).
///
/// The index is rebuilt from storage — never patched — at launch, when a sync
/// finishes (the app lists are what a sync writes) and on every
/// `accountsDidChange` (create, import, delete: a deleted account's apps are
/// gone from storage, so they leave the index). Only what the UI shows is
/// indexed: visible stores, the per-app scope, no archived apps.
@MainActor
final class AppSpotlightIndexer {

    /// Built on first access, after `StackConnectApp` installed
    /// `SwiftDataStorable.shared`.
    static let shared = AppSpotlightIndexer()

    private let storage: PersistentStorable
    private let writer: AppSpotlightIndexWriting
    private let featureFlags: FeatureFlags
    private let notificationCenter: NotificationCenter
    private var subscriptions = Set<AnyCancellable>()

    /// The rebuild started last. Exposed so tests can await it.
    private(set) var pendingRebuild: Task<Void, Never>?

    init(
        storage: PersistentStorable? = nil,
        writer: AppSpotlightIndexWriting = CoreSpotlightIndexWriter(),
        featureFlags: FeatureFlags = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.writer = writer
        self.featureFlags = featureFlags
        self.notificationCenter = notificationCenter
    }

    /// Rebuilds now, then after every finished sync of `syncState` and every
    /// account change. Calling it again only rebuilds.
    func start(syncState: AnyPublisher<SyncState, Never>) {
        if subscriptions.isEmpty {
            notificationCenter.publisher(for: .accountsDidChange)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleRebuild() }
                }
                .store(in: &subscriptions)
            syncState
                .map(\.isSyncing)
                .removeDuplicates()
                .dropFirst()
                .filter { !$0 }
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleRebuild() }
                }
                .store(in: &subscriptions)
        }
        scheduleRebuild()
    }

    /// Coalesces bursts ("Delete all accounts" posts once per account): a new
    /// rebuild cancels the one in flight, which writes nothing once cancelled.
    func scheduleRebuild() {
        pendingRebuild?.cancel()
        pendingRebuild = Task { [weak self] in await self?.rebuild() }
    }

    func rebuild() async {
        do {
            let accounts = featureFlags.visibleAccounts(try await storage.fetchAll(AccountModel.self))
            let apps = try await storage.fetchAll(AppModel.self)
            var playApps: [String: [GooglePlayAppItem]] = [:]
            for account in accounts where account.providerType == .googlePlay {
                playApps[account.id] = (try? await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: account.id))) ?? nil
            }
            let entries = Self.entries(accounts: accounts, apps: apps, googlePlayApps: playApps)
            guard !Task.isCancelled else { return }
            try await writer.replaceAll(with: entries)
            Log.print.info("[Spotlight] Indexed \(entries.count) apps")
        } catch {
            Log.print.error("[Spotlight] Index not updated: \(error.localizedDescription)")
        }
    }

    // MARK: - Pure mapping

    /// The entries for `accounts` (already narrowed to the visible stores):
    /// App Store Connect apps from `apps`, Google Play apps from
    /// `googlePlayApps` (keyed by account id). Archived apps and apps outside
    /// an account's scope are left out; Firebase has no apps to index.
    static func entries(
        accounts: [AccountModel],
        apps: [AppModel],
        googlePlayApps: [String: [GooglePlayAppItem]]
    ) -> [AppSpotlightEntry] {
        accounts.flatMap { account -> [AppSpotlightEntry] in
            switch account.providerType {
            case .apple:
                return apps
                    .filter { $0.accountId == account.id && !$0.isArchived && account.allowsApp(bundleId: $0.bundleId) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map { app in
                        AppSpotlightEntry(
                            url: DeepLink.app(accountId: account.id, appId: app.id).url,
                            accountId: account.id,
                            name: app.name,
                            bundleId: app.bundleId
                        )
                    }
            case .googlePlay:
                return (googlePlayApps[account.id] ?? [])
                    .filter { !$0.isArchived && account.allowsApp(bundleId: $0.packageName) }
                    .map { app in
                        AppSpotlightEntry(
                            url: DeepLink.app(accountId: account.id, appId: app.packageName).url,
                            accountId: account.id,
                            name: app.displayName,
                            bundleId: app.packageName
                        )
                    }
            case .firebase:
                return []
            }
        }
    }

    /// The deep link of a Spotlight result the user tapped
    /// (`CSSearchableItemActionType`), or `nil` for anything else.
    nonisolated static func deepLinkURL(from userInfo: [AnyHashable: Any]?) -> URL? {
        guard let identifier = userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier),
              DeepLink(url: url) != nil else { return nil }
        return url
    }
}
