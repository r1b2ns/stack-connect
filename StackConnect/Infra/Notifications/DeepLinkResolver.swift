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

/// Where an entry-point link (`testflight`, `remote-config`, `certificates`)
/// lands. Those links carry no account or app (App Store custom product pages
/// and In-App Events, App Shortcuts), so the landing depends on what the user
/// has: straight to the screen when there is only one candidate, the list to
/// pick from otherwise.
enum DeepLinkLanding: Equatable {
    /// No account of the link's store yet: the Home, whose empty state offers
    /// to add one (as `home` and `reviews` show their empty states).
    case home
    /// Several accounts could answer, or none can right now (expired, no
    /// permission): the unified accounts list, where the user picks one and
    /// sees why another is locked.
    case accountChooser
    /// One account: the list of that section (its apps / Firebase projects,
    /// its certificates).
    case accountSection(AccountModel, RootAccountSection)
    /// One app overall: its TestFlight, over its App Detail.
    case testFlight(AppModel, account: AccountModel)
    /// One Firebase account scoped to one project (known offline, from
    /// `appsBundles`): that project's Remote Config, over the project list.
    case remoteConfig(FirebaseProjectModel, account: AccountModel)
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
        case .home, .reviews, .networkAudit, .testFlight, .remoteConfig, .certificates, .reimport:
            return nil
        }
    }

    /// The landing of an entry-point link; `nil` for every other link.
    func landing(for link: DeepLink) async -> DeepLinkLanding? {
        switch link {
        case .testFlight:
            return await testFlightLanding()
        case .remoteConfig:
            return await remoteConfigLanding()
        case .certificates:
            return await certificatesLanding()
        case .home, .reviews, .networkAudit, .app, .review, .reimport:
            return nil
        }
    }

    // MARK: - Entry points

    /// TestFlight is per app: the app's TestFlight when the user has exactly
    /// one (non-archived) app they may test, else the app list of the only
    /// account, else the accounts list.
    private func testFlightLanding() async -> DeepLinkLanding {
        let accounts = await visibleAccounts(of: .apple)
        guard !accounts.isEmpty else { return .home }
        let usable = accounts.filter { !$0.isExpired && $0.canView(.testFlight) }
        guard !usable.isEmpty else { return .accountChooser }

        let allApps = (try? await storage.fetchAll(AppModel.self)) ?? []
        let candidates: [(AppModel, AccountModel)] = usable.flatMap { account in
            allApps
                .filter { $0.accountId == account.id && !$0.isArchived && account.allowsApp(bundleId: $0.bundleId) }
                .map { ($0, account) }
        }
        if candidates.count == 1, let only = candidates.first {
            return .testFlight(only.0, account: only.1)
        }
        if usable.count == 1, let account = usable.first {
            return .accountSection(account, .apps)
        }
        return .accountChooser
    }

    /// Firebase projects are fetched live (never cached), so a project is
    /// only known offline when the only Firebase account is scoped to one.
    private func remoteConfigLanding() async -> DeepLinkLanding {
        let accounts = await visibleAccounts(of: .firebase)
        guard !accounts.isEmpty else { return .home }
        let usable = accounts.filter { !$0.isExpired }
        guard usable.count == 1, let account = usable.first else { return .accountChooser }
        if let scope = account.appsBundles, scope.count == 1, let projectId = scope.first {
            // Remote Config reads the project id only; the list behind it
            // loads the real project.
            let project = FirebaseProjectModel(id: projectId, displayName: projectId, projectId: projectId)
            return .remoteConfig(project, account: account)
        }
        return .accountSection(account, .apps)
    }

    /// Certificates belong to App Store Connect accounts allowed to view
    /// provisioning (the rule of Manage Account and the split view sidebar).
    private func certificatesLanding() async -> DeepLinkLanding {
        let accounts = await visibleAccounts(of: .apple)
        guard !accounts.isEmpty else { return .home }
        let usable = accounts.filter {
            !$0.isExpired && $0.ruleResources.contains(.provisioning) && $0.canView(.provisioning)
        }
        guard usable.count == 1, let account = usable.first else { return .accountChooser }
        return .accountSection(account, .certificates)
    }

    /// Stored accounts of `provider` the UI may show, legacy rules filled in.
    private func visibleAccounts(of provider: ProviderType) async -> [AccountModel] {
        let all = (try? await storage.fetchAll(AccountModel.self)) ?? []
        return featureFlags.visibleAccounts(all)
            .filter { $0.providerType == provider }
            .map { account in
                var account = account
                account.fillMissingRules()
                return account
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
