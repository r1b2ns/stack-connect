import Foundation

// MARK: - Group

/// The accounts of one store, as one section of the unified accounts lists
/// (Home › Accounts and Settings › Accounts).
struct AccountProviderGroup: Identifiable, Hashable {
    let provider: ProviderType
    /// In name order.
    let accounts: [AccountModel]

    var id: String { provider.rawValue }
}

// MARK: - Listing

/// The single rule of the unified accounts lists: one group per available
/// store, in the order App Store Connect, Google Play, Firebase, and the
/// search that filters them (plan `unified-accounts.md` §2).
enum AccountsListing {

    /// Groups `accounts` by store, skipping stores without accounts.
    /// - Parameter providers: the available stores (`FeatureFlags.availableProviders`):
    ///   accounts of any other store are left out.
    static func groups(of accounts: [AccountModel], providers: [ProviderType]) -> [AccountProviderGroup] {
        providers
            .sorted { AccountWizardConfig.displayOrder($0) < AccountWizardConfig.displayOrder($1) }
            .compactMap { provider in
                let matching = accounts
                    .filter { $0.providerType == provider }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return matching.isEmpty ? nil : AccountProviderGroup(provider: provider, accounts: matching)
            }
    }

    /// `groups` narrowed to the accounts matching `query`; groups left empty
    /// are dropped. An empty (or blank) query keeps everything.
    static func filter(_ groups: [AccountProviderGroup], query: String) -> [AccountProviderGroup] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let matching = group.accounts.filter { matches($0, needle: needle) }
            return matching.isEmpty ? nil : AccountProviderGroup(provider: group.provider, accounts: matching)
        }
    }

    /// Whether `account` matches `query`: its name, its store or how it is
    /// connected ("API Key", "Apple ID", "Service Account Key", "Google Account").
    static func matches(_ account: AccountModel, query: String) -> Bool {
        let needle = normalized(query)
        return needle.isEmpty || matches(account, needle: needle)
    }

    private static func matches(_ account: AccountModel, needle: String) -> Bool {
        let haystack = [
            account.name,
            account.providerType.displayName,
            account.connection.title
        ]
        return haystack.contains { normalized($0).contains(needle) }
    }

    /// Case-, diacritic- and width-insensitive, trimmed.
    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

// MARK: - Summary

/// The "Summary" of the Accounts rows (Settings, Home): how many accounts,
/// how many need attention, and how many per store.
struct AccountsSummary: Equatable {

    struct ProviderCount: Equatable, Identifiable {
        let provider: ProviderType
        let count: Int
        var id: String { provider.rawValue }
    }

    let total: Int
    /// Accounts with any status (disconnected, reconnecting or action needed).
    let needsAttention: Int
    /// One entry per available store with at least one account, in list order.
    let providers: [ProviderCount]

    static let empty = AccountsSummary(total: 0, needsAttention: 0, providers: [])

    init(total: Int, needsAttention: Int, providers: [ProviderCount]) {
        self.total = total
        self.needsAttention = needsAttention
        self.providers = providers
    }

    /// - Parameters:
    ///   - accounts: the visible accounts.
    ///   - statuses: their statuses, keyed by account id (accounts without one are absent).
    ///   - providers: the available stores.
    init(accounts: [AccountModel], statuses: [String: AccountStatus], providers: [ProviderType]) {
        let groups = AccountsListing.groups(of: accounts, providers: providers)
        let shown = groups.flatMap(\.accounts)
        self.total = shown.count
        self.needsAttention = shown.filter { statuses[$0.id] != nil }.count
        self.providers = groups.map { ProviderCount(provider: $0.provider, count: $0.accounts.count) }
    }
}

// MARK: - List state

/// What both unified accounts lists show (Home › Accounts, Settings ›
/// Accounts): the groups, the search and the account statuses.
struct AccountsListingState {
    /// Every visible account, in list order (stores hidden by a flag are left out).
    var accounts: [AccountModel] = []
    /// One group per store with accounts, before the search.
    var groups: [AccountProviderGroup] = []
    /// `.searchable` text: matches the name, the store and the connection.
    var query = ""
    var isLoading = false
    var hasLoaded = false
    /// Problems of the listed accounts (`AccountStatusResolving`), keyed by
    /// account id; accounts without one are absent (connected).
    var accountStatuses: [String: AccountStatus] = [:]

    /// What the list renders: `groups` narrowed by `query`.
    var visibleGroups: [AccountProviderGroup] {
        AccountsListing.filter(groups, query: query)
    }

    var visibleCount: Int {
        visibleGroups.reduce(0) { $0 + $1.accounts.count }
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A search found nothing (there are accounts).
    var showsNoResults: Bool {
        isSearching && visibleGroups.isEmpty && !accounts.isEmpty
    }

    /// Shows what `snapshot` read, keeping the query typed meanwhile.
    mutating func apply(_ snapshot: AccountsListingSnapshot) {
        groups = snapshot.groups
        accounts = snapshot.groups.flatMap(\.accounts)
        accountStatuses = snapshot.statuses
    }
}

/// The visible accounts, grouped, and their statuses, read from storage.
struct AccountsListingSnapshot {
    let groups: [AccountProviderGroup]
    let statuses: [String: AccountStatus]

    @MainActor
    static func load(storage: PersistentStorable, featureFlags: FeatureFlags, statusProvider: AccountStatusProviding) async throws -> AccountsListingSnapshot {
        var accounts = featureFlags.visibleAccounts(try await storage.fetchAll(AccountModel.self))
        // Fill missing rules for legacy accounts.
        for index in accounts.indices { accounts[index].fillMissingRules() }
        let groups = AccountsListing.groups(of: accounts, providers: featureFlags.availableProviders)
        return AccountsListingSnapshot(groups: groups, statuses: statusProvider.statuses(for: groups.flatMap(\.accounts)))
    }
}
