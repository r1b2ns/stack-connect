import Foundation

/// Removes an account together with the local data scoped to it.
///
/// Account deletion is reachable from several screens (Settings → Accounts, the
/// per-provider Accounts list, Account Management and Settings → "Delete all
/// accounts"). They all go through this single cascade so a new account-scoped
/// model only has to be wired in once — keeping a copy per screen is how reply
/// templates ended up orphaned after their account was deleted.
///
/// What is removed, in this order:
/// 1. the account's apps (`"<accountId>.<appId>"`) and those apps' versions
///    (`"version.<versionId>"`);
/// 2. the account's reply templates (`ReplyTemplateModel.id`) — templates of
///    other accounts are left untouched;
/// 3. the account's cached Google Play app list
///    (`GooglePlayAppItem.cacheKey(accountId:)`, a no-op for other providers);
/// 4. the account's per-app Google Play caches — app details, store listings,
///    tracks and reviews (`GooglePlayAppScopedCache`), found by `accountId` so
///    apps that left the cached list are covered too;
/// 5. the `AccountModel` itself (`account.id`);
/// 6. the keychain credentials (`"credentials.<accountId>"`).
///
/// Error semantics:
/// - Reads propagate. They all run before anything is deleted, so a failed read
///   leaves storage untouched and the caller can simply retry.
/// - Deleting child items (versions, apps, templates, the Play caches) is
///   best-effort: one failure does not stop the cascade.
/// - Deleting the `AccountModel` propagates. When it fails the keychain
///   credentials are kept, so the still-stored account remains usable.
///
/// `@MainActor` because every caller is a `@MainActor` ViewModel and `KeyStorable`
/// is not `Sendable`: isolating the helper keeps the keychain on the caller's
/// actor instead of sending it across isolation domains.
@MainActor
enum AccountCascadeDeleter {

    static func delete(
        _ account: AccountModel,
        storage: PersistentStorable,
        keychain: KeyStorable
    ) async throws {
        let accountApps = try await storage.fetchAll(AppModel.self)
            .filter { $0.accountId == account.id }

        // Versions are read once (not once per app) and only when there is an
        // app to match them against — an account without apps never needed them.
        var versionsByAppId: [String: [AppStoreVersionModel]] = [:]
        if !accountApps.isEmpty {
            let allVersions = try await storage.fetchAll(AppStoreVersionModel.self)
            versionsByAppId = Dictionary(grouping: allVersions, by: \.appId)
        }

        let accountTemplates = try await storage.fetchAll(ReplyTemplateModel.self)
            .filter { $0.accountId == account.id }

        // Only Google Play accounts own per-app Play caches.
        let googlePlayCacheDeletions: [() async -> Void]
        if account.providerType == .googlePlay {
            googlePlayCacheDeletions = try await
                scopedCacheDeletions(GooglePlayAppDetailsCache.self, accountId: account.id, storage: storage)
                + scopedCacheDeletions(GooglePlayStoreListingsCache.self, accountId: account.id, storage: storage)
                + scopedCacheDeletions(GooglePlayTracksCache.self, accountId: account.id, storage: storage)
                + scopedCacheDeletions(GooglePlayReviewsCache.self, accountId: account.id, storage: storage)
        } else {
            googlePlayCacheDeletions = []
        }

        for app in accountApps {
            for version in versionsByAppId[app.id] ?? [] {
                try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
            }
            try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
        }

        for template in accountTemplates {
            try? await storage.delete(ReplyTemplateModel.self, id: template.id)
        }

        try? await storage.delete(
            [GooglePlayAppItem].self,
            id: GooglePlayAppItem.cacheKey(accountId: account.id)
        )

        for deletion in googlePlayCacheDeletions {
            await deletion()
        }

        try await storage.delete(AccountModel.self, id: account.id)
        keychain.removeObject(forKey: "credentials.\(account.id)")
    }

    /// Reads every `Entry` of `accountId` now (so a read failure propagates
    /// before anything is deleted) and returns one best-effort deletion per entry.
    private static func scopedCacheDeletions<Entry: GooglePlayAppScopedCache>(
        _ type: Entry.Type,
        accountId: String,
        storage: PersistentStorable
    ) async throws -> [() async -> Void] {
        try await storage.fetchAll(Entry.self)
            .filter { $0.accountId == accountId }
            .map { entry in
                let id = entry.cacheKey
                return { try? await storage.delete(Entry.self, id: id) }
            }
    }
}
