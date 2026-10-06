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
/// 4. the `AccountModel` itself (`account.id`);
/// 5. the keychain credentials (`"credentials.<accountId>"`).
///
/// Error semantics:
/// - Reads propagate. They all run before anything is deleted, so a failed read
///   leaves storage untouched and the caller can simply retry.
/// - Deleting child items (versions, apps, templates, the Play app cache) is
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

        try await storage.delete(AccountModel.self, id: account.id)
        keychain.removeObject(forKey: "credentials.\(account.id)")
    }
}
