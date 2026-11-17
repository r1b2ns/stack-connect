import Foundation

/// Builds the reviews backend of an account from its stored credentials, so the
/// review screens never branch on the provider themselves.
@MainActor
enum CustomerReviewsServiceFactory {

    /// `nil` when the account has no stored credentials or its provider has no
    /// reviews (Firebase).
    static func makeService(for account: AccountModel) -> (any CustomerReviewsServicing)? {
        makeService(for: account, keychain: KeychainStorable.shared)
    }

    static func makeService(for account: AccountModel, keychain: KeyStorable) -> (any CustomerReviewsServicing)? {
        let key = "credentials.\(account.id)"
        switch account.providerType {
        case .apple:
            guard let credentials: AppleCredentials = keychain.object(forKey: key) else { return nil }
            return AppleCustomerReviewsService(connection: AppleAccountConnection(credentials: credentials))
        case .googlePlay:
            guard let credentials: GooglePlayCredentials = keychain.object(forKey: key) else { return nil }
            return GooglePlayCustomerReviewsService(connection: GooglePlayAccountConnection(credentials: credentials))
        case .firebase:
            return nil
        }
    }

    /// Offline cache of the app's first page of reviews. Google Play only: App
    /// Store reviews are cached by `SyncService` for the Home dashboard, and the
    /// App Store list keeps loading live as it always did.
    static func makeCache(for account: AccountModel, appId: String) -> (any CustomerReviewsCaching)? {
        makeCache(for: account, appId: appId, storage: SwiftDataStorable.shared)
    }

    static func makeCache(for account: AccountModel, appId: String, storage: PersistentStorable) -> (any CustomerReviewsCaching)? {
        guard account.providerType == .googlePlay else { return nil }
        return GooglePlayCustomerReviewsCache(storage: storage, accountId: account.id, packageName: appId)
    }
}
