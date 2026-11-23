import Foundation

/// Where an `app` or `review` deep link leads once its account is known
/// (plan H7): the account's provider decides between the App Store and the
/// Google Play screens.
enum DeepLinkDestination: Equatable {
    case appStoreApp(AppModel, account: AccountModel)
    case googlePlayApp(GooglePlayAppItem, account: AccountModel)
    /// `appId` is set for Google Play (the package), so Review Detail keeps the
    /// Play reviews cache in step after a reply.
    case review(CustomerReviewModel, appName: String, account: AccountModel, appId: String?)
}

/// Resolves the `app` and `review` deep links of widgets and local
/// notifications from storage. `nil` when the account, the app or the review
/// is gone.
struct DeepLinkResolver {

    let storage: PersistentStorable
    /// Links to an account of a hidden store (Google Play while
    /// `googlePlayAccounts` is OFF) resolve to nothing.
    var featureFlags: FeatureFlags = .shared

    func resolve(_ link: DeepLink) async -> DeepLinkDestination? {
        switch link {
        case let .app(accountId, appId):
            return await resolveApp(accountId: accountId, appId: appId)
        case let .review(accountId, appId, reviewId):
            return await resolveReview(accountId: accountId, appId: appId, reviewId: reviewId)
        case .home, .reviews, .reimport:
            return nil
        }
    }

    private func account(_ accountId: String) async -> AccountModel? {
        guard var account = (try? await storage.fetch(AccountModel.self, id: accountId)) ?? nil,
              featureFlags.isVisible(account) else { return nil }
        account.fillMissingRules()
        return account
    }

    private func googlePlayApp(packageName: String, accountId: String) async -> GooglePlayAppItem? {
        let list = (try? await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: accountId))) ?? nil
        return list?.first { $0.packageName == packageName }
    }

    private func resolveApp(accountId: String, appId: String) async -> DeepLinkDestination? {
        guard let account = await account(accountId) else { return nil }
        switch account.providerType {
        case .googlePlay:
            guard let app = await googlePlayApp(packageName: appId, accountId: accountId) else { return nil }
            return .googlePlayApp(app, account: account)
        case .apple:
            guard let app = (try? await storage.fetch(AppModel.self, id: "\(accountId).\(appId)")) ?? nil else { return nil }
            return .appStoreApp(app, account: account)
        case .firebase:
            return nil
        }
    }

    private func resolveReview(accountId: String, appId: String, reviewId: String) async -> DeepLinkDestination? {
        guard let account = await account(accountId),
              let review = (try? await storage.fetch(CustomerReviewModel.self, id: CustomerReviewModel.storageId(appId: appId, reviewId: reviewId))) ?? nil
        else { return nil }
        switch account.providerType {
        case .googlePlay:
            guard let app = await googlePlayApp(packageName: appId, accountId: accountId) else { return nil }
            return .review(review, appName: app.displayName, account: account, appId: appId)
        case .apple:
            guard let app = (try? await storage.fetch(AppModel.self, id: "\(accountId).\(appId)")) ?? nil else { return nil }
            return .review(review, appName: app.name, account: account, appId: nil)
        case .firebase:
            return nil
        }
    }
}
