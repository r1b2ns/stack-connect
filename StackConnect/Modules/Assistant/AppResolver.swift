import Foundation

/// Resolves user-provided app names/identifiers into `AppModel`s and looks up
/// the owning account. Reads exclusively from the on-device cache (SwiftData),
/// so it works offline and never touches the network.
protocol AppResolving: Sendable {
    func allApps() async -> [AppModel]
    func apps(matching query: String) async -> [AppModel]
    func account(for app: AppModel) async -> AccountModel?
}

struct AppResolver: AppResolving {

    private let storage: any PersistentStorable

    init(storage: any PersistentStorable) {
        self.storage = storage
    }

    /// All non-archived apps cached on the device.
    func allApps() async -> [AppModel] {
        let apps = (try? await storage.fetchAll(AppModel.self)) ?? []
        return apps.filter { !$0.isArchived }
    }

    /// Apps matching `query`. An exact (case-insensitive) match on name or
    /// bundle id wins outright; otherwise falls back to a "contains" search.
    /// A blank query returns all non-archived apps.
    func apps(matching query: String) async -> [AppModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = await allApps()
        guard !trimmed.isEmpty else { return all }

        let exact = all.filter {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.bundleId.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !exact.isEmpty { return exact }

        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.bundleId.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// The account that owns `app`, with missing rules filled in (mirrors how
    /// the rest of the app prepares accounts before permission checks).
    func account(for app: AppModel) async -> AccountModel? {
        guard var account = try? await storage.fetch(AccountModel.self, id: app.accountId) else {
            return nil
        }
        account.fillMissingRules()
        return account
    }
}
