import SwiftUI

enum HomeRoute: Hashable {
    case settings
    case settingsAccounts
    case license
    case tipJar
    case accountSettings(AccountModel)
    case accountManagement(AccountModel)
    case certificatesList(AccountModel)
    case createCertificate(AccountModel)
    case certificateDetail(certificate: CertificateModel, account: AccountModel)
    case profilesList(AccountModel)
    case createProfile(AccountModel)
    case profileDetail(profile: ProvisioningProfileModel, account: AccountModel)
    case identifiersList(AccountModel)
    case identifierDetail(bundleId: BundleIdentifierModel, account: AccountModel)
    case devicesList(AccountModel)
    case deviceDetail(device: DeviceModel, account: AccountModel)
    case importDevices(AccountModel)
    case accountsList(ProviderType)
    case appList(AccountModel)
    case firebaseProjectList(AccountModel)
    case firebaseProjectDetail(project: FirebaseProjectModel, account: AccountModel)
    case firebaseAppList(project: FirebaseProjectModel, account: AccountModel)
    case remoteConfig(project: FirebaseProjectModel, account: AccountModel)
    case analyticsDashboard(project: FirebaseProjectModel, account: AccountModel)
    case messaging(project: FirebaseProjectModel, account: AccountModel)
    case googlePlayAppList(AccountModel)
    case googlePlayAppDetail(app: GooglePlayAppItem, account: AccountModel)
    case googlePlayStoreListings(app: GooglePlayAppItem, account: AccountModel)
    case googlePlayStoreListingDetail(listing: GooglePlayStoreListingModel, isDefaultLanguage: Bool)
    case googlePlayTracks(app: GooglePlayAppItem, account: AccountModel)
    case googlePlayReleaseDetail(app: GooglePlayAppItem, account: AccountModel, track: String, release: GooglePlayReleaseModel)
    case googlePlayAppInfo(app: GooglePlayAppItem, account: AccountModel)
    case googlePlayUserDetail(user: GooglePlayUserModel, account: AccountModel)
    case appDetail(app: AppModel, account: AccountModel)
    case versionList(appId: String, platform: AppPlatform, account: AccountModel)
    case versionDetail(version: AppStoreVersionModel, account: AccountModel)
    case screenshotPreview(versionId: String, localizationId: String?, platform: AppPlatform?, appStoreState: AppStoreState?, account: AccountModel)
    case screenshotResolution(device: ScreenshotDeviceType, sets: [ScreenshotSetModel], account: AccountModel, appStoreState: AppStoreState?)
    case screenshotGrid(screenshots: [ScreenshotModel], account: AccountModel, appStoreState: AppStoreState?)
    case screenshotPage(screenshots: [ScreenshotModel], startIndex: Int, account: AccountModel, appStoreState: AppStoreState?)
    case appReviewInfo(versionId: String, account: AccountModel)
    case betaAppReviewInfo(appId: String, account: AccountModel)
    case appInformation(app: AppModel, account: AccountModel)
    case ageRating(ageRating: AgeRatingDeclarationModel, account: AccountModel)
    case manageLocalizations(appInfoId: String, primaryLocale: String, account: AccountModel)
    case appCategoryPicker(appInfoId: String, primaryCategoryId: String?, primarySubcategoryId: String?, secondaryCategoryId: String?, secondarySubcategoryId: String?, account: AccountModel)
    case archivedApps(account: AccountModel)
    case submissions(appId: String, appName: String?, account: AccountModel)
    case reviewSubmissionDetail(submission: ReviewSubmissionModel, account: AccountModel)
    case appHistory(appId: String, account: AccountModel)
    case appPrivacy(appId: String, account: AccountModel)
    case appAccessibility(appId: String, account: AccountModel)
    case ratingsReviews(appId: String, bundleId: String, appName: String, account: AccountModel)
    /// `appId` (the package name for Google Play) lets the detail keep the
    /// store's offline reviews cache in step after a reply; `nil` from screens
    /// that aren't an app's review list.
    case reviewDetail(review: CustomerReviewModel, appName: String, account: AccountModel, appId: String? = nil)
    case allReviews
    case testFlight(appId: String, account: AccountModel)
    case betaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel)
    case betaGroupTesters(group: BetaGroupModel, appId: String, account: AccountModel)
    case platformBuildsList(appId: String, platform: String, account: AccountModel)
    case buildDetail(build: BuildModel, appId: String, account: AccountModel)
    case userDetail(user: UserModel, account: AccountModel)
    case analyticsReports(appId: String, appName: String, account: AccountModel)
    case analyticsReportDetail(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel)
    case analyticsReportFiles(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel)
}

final class HomeCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()

    /// When set, every route is handed to this closure instead of being pushed
    /// on `path`. The regular-width split view uses it for its content column:
    /// a row tapped in the middle column opens in the detail column instead of
    /// pushing inside the narrow list (`RootSplitCoordinator`).
    var routeHandler: ((HomeRoute) -> Void)?

    /// When set, `popToRoot()` calls this closure instead of emptying `path`.
    /// The split view uses it to go back to its dashboard after an account is
    /// deleted, since there is no single stack to unwind there.
    var popToRootHandler: (() -> Void)?

    init(routeHandler: ((HomeRoute) -> Void)? = nil, popToRootHandler: (() -> Void)? = nil) {
        self.routeHandler = routeHandler
        self.popToRootHandler = popToRootHandler
    }

    /// Single funnel for every `navigateTo…` call.
    func push(_ route: HomeRoute) {
        if let routeHandler {
            routeHandler(route)
        } else {
            path.append(route)
        }
    }

    /// Shadows `MainCoordinatorProtocol.popToRoot()` for callers holding a
    /// `HomeCoordinator` (every screen reads it from the environment).
    func popToRoot() {
        if let popToRootHandler {
            popToRootHandler()
        } else {
            path.removeLast(path.count)
        }
    }

    func navigateToSettings() {
        push(HomeRoute.settings)
    }

    func navigateToSettingsAccounts() {
        push(HomeRoute.settingsAccounts)
    }

    func navigateToLicense() {
        push(HomeRoute.license)
    }

    func navigateToTipJar() {
        push(HomeRoute.tipJar)
    }

    func navigateToAccountSettings(_ account: AccountModel) {
        push(HomeRoute.accountSettings(account))
    }

    func navigateToAccountManagement(_ account: AccountModel) {
        push(HomeRoute.accountManagement(account))
    }

    func navigateToCertificatesList(_ account: AccountModel) {
        push(HomeRoute.certificatesList(account))
    }

    func navigateToCertificateDetail(certificate: CertificateModel, account: AccountModel) {
        push(HomeRoute.certificateDetail(certificate: certificate, account: account))
    }

    func navigateToCreateCertificate(_ account: AccountModel) {
        push(HomeRoute.createCertificate(account))
    }

    func navigateToProfilesList(_ account: AccountModel) {
        push(HomeRoute.profilesList(account))
    }

    func navigateToCreateProfile(_ account: AccountModel) {
        push(HomeRoute.createProfile(account))
    }

    func navigateToProfileDetail(profile: ProvisioningProfileModel, account: AccountModel) {
        push(HomeRoute.profileDetail(profile: profile, account: account))
    }

    func navigateToIdentifiersList(_ account: AccountModel) {
        push(HomeRoute.identifiersList(account))
    }

    func navigateToIdentifierDetail(bundleId: BundleIdentifierModel, account: AccountModel) {
        push(HomeRoute.identifierDetail(bundleId: bundleId, account: account))
    }

    func navigateToDevicesList(_ account: AccountModel) {
        push(HomeRoute.devicesList(account))
    }

    func navigateToDeviceDetail(device: DeviceModel, account: AccountModel) {
        push(HomeRoute.deviceDetail(device: device, account: account))
    }

    func navigateToImportDevices(_ account: AccountModel) {
        push(HomeRoute.importDevices(account))
    }

    func navigateToAccountsList(_ providerType: ProviderType) {
        push(HomeRoute.accountsList(providerType))
    }

    func navigateToAppList(_ account: AccountModel) {
        push(HomeRoute.appList(account))
    }

    func navigateToFirebaseProjectList(_ account: AccountModel) {
        push(HomeRoute.firebaseProjectList(account))
    }

    func navigateToFirebaseProjectDetail(project: FirebaseProjectModel, account: AccountModel) {
        push(HomeRoute.firebaseProjectDetail(project: project, account: account))
    }

    func navigateToFirebaseAppList(project: FirebaseProjectModel, account: AccountModel) {
        push(HomeRoute.firebaseAppList(project: project, account: account))
    }

    func navigateToRemoteConfig(project: FirebaseProjectModel, account: AccountModel) {
        push(HomeRoute.remoteConfig(project: project, account: account))
    }

    func navigateToAnalyticsDashboard(project: FirebaseProjectModel, account: AccountModel) {
        push(HomeRoute.analyticsDashboard(project: project, account: account))
    }

    func navigateToMessaging(project: FirebaseProjectModel, account: AccountModel) {
        push(HomeRoute.messaging(project: project, account: account))
    }

    func navigateToGooglePlayAppList(_ account: AccountModel) {
        push(HomeRoute.googlePlayAppList(account))
    }

    func navigateToGooglePlayAppDetail(_ app: GooglePlayAppItem, account: AccountModel) {
        push(HomeRoute.googlePlayAppDetail(app: app, account: account))
    }

    func navigateToGooglePlayStoreListings(_ app: GooglePlayAppItem, account: AccountModel) {
        push(HomeRoute.googlePlayStoreListings(app: app, account: account))
    }

    func navigateToGooglePlayStoreListingDetail(_ listing: GooglePlayStoreListingModel, isDefaultLanguage: Bool) {
        push(HomeRoute.googlePlayStoreListingDetail(listing: listing, isDefaultLanguage: isDefaultLanguage))
    }

    func navigateToGooglePlayTracks(_ app: GooglePlayAppItem, account: AccountModel) {
        push(HomeRoute.googlePlayTracks(app: app, account: account))
    }

    func navigateToGooglePlayReleaseDetail(_ release: GooglePlayReleaseModel, track: String, app: GooglePlayAppItem, account: AccountModel) {
        push(HomeRoute.googlePlayReleaseDetail(app: app, account: account, track: track, release: release))
    }

    func navigateToGooglePlayAppInfo(_ app: GooglePlayAppItem, account: AccountModel) {
        push(HomeRoute.googlePlayAppInfo(app: app, account: account))
    }

    func navigateToGooglePlayUserDetail(_ user: GooglePlayUserModel, account: AccountModel) {
        push(HomeRoute.googlePlayUserDetail(user: user, account: account))
    }

    func navigateToAppDetail(_ app: AppModel, account: AccountModel) {
        push(HomeRoute.appDetail(app: app, account: account))
    }

    /// Opens a dashboard row's app in its own store's detail (plan H7).
    func navigate(to target: DashboardTarget, account: AccountModel) {
        switch target {
        case .appStore(let app):
            navigateToAppDetail(app, account: account)
        case .googlePlay(let app):
            navigateToGooglePlayAppDetail(app, account: account)
        }
    }

    /// Opens a dashboard row; when the widget couldn't read the accounts, the
    /// row's account is resolved from storage first (a row whose account is
    /// gone does nothing, logged).
    @MainActor
    func open(_ target: DashboardTarget, accountId: String, account: AccountModel?, storage: PersistentStorable? = SwiftDataStorable.shared) {
        if let account {
            navigate(to: target, account: account)
            return
        }
        Task { @MainActor in
            guard var resolved = try? await storage?.fetch(AccountModel.self, id: accountId),
                  FeatureFlags.shared.isVisible(resolved) else {
                Log.print.notice("[Home] Dashboard row references unknown account \(accountId, privacy: .public)")
                return
            }
            resolved.fillMissingRules()
            navigate(to: target, account: resolved)
        }
    }

    /// Opens a dashboard review in Review Detail (Play reviews carry their
    /// package so the detail keeps the Play reviews cache in step).
    @MainActor
    func open(_ item: DashboardReview, storage: PersistentStorable? = SwiftDataStorable.shared) {
        let appId = item.provider == .googlePlay ? item.appId : nil
        if let account = item.account {
            navigateToReviewDetail(review: item.review, appName: item.appName, account: account, appId: appId)
            return
        }
        Task { @MainActor in
            guard var resolved = try? await storage?.fetch(AccountModel.self, id: item.accountId),
                  FeatureFlags.shared.isVisible(resolved) else {
                Log.print.notice("[Home] Dashboard review references unknown account \(item.accountId, privacy: .public)")
                return
            }
            resolved.fillMissingRules()
            navigateToReviewDetail(review: item.review, appName: item.appName, account: resolved, appId: appId)
        }
    }

    func navigateToVersionList(appId: String, platform: AppPlatform, account: AccountModel) {
        push(HomeRoute.versionList(appId: appId, platform: platform, account: account))
    }

    func navigateToVersionDetail(_ version: AppStoreVersionModel, account: AccountModel) {
        push(HomeRoute.versionDetail(version: version, account: account))
    }

    func navigateToScreenshotPreview(versionId: String, account: AccountModel, localizationId: String? = nil, platform: AppPlatform? = nil, appStoreState: AppStoreState? = nil) {
        push(HomeRoute.screenshotPreview(versionId: versionId, localizationId: localizationId, platform: platform, appStoreState: appStoreState, account: account))
    }

    func navigateToScreenshotResolution(device: ScreenshotDeviceType, sets: [ScreenshotSetModel], account: AccountModel, appStoreState: AppStoreState?) {
        push(HomeRoute.screenshotResolution(device: device, sets: sets, account: account, appStoreState: appStoreState))
    }

    func navigateToScreenshotGrid(screenshots: [ScreenshotModel], account: AccountModel, appStoreState: AppStoreState?) {
        push(HomeRoute.screenshotGrid(screenshots: screenshots, account: account, appStoreState: appStoreState))
    }

    func navigateToScreenshotPage(screenshots: [ScreenshotModel], startIndex: Int = 0, account: AccountModel, appStoreState: AppStoreState?) {
        push(HomeRoute.screenshotPage(screenshots: screenshots, startIndex: startIndex, account: account, appStoreState: appStoreState))
    }

    func navigateToAppReviewInfo(versionId: String, account: AccountModel) {
        push(HomeRoute.appReviewInfo(versionId: versionId, account: account))
    }

    func navigateToBetaAppReviewInfo(appId: String, account: AccountModel) {
        push(HomeRoute.betaAppReviewInfo(appId: appId, account: account))
    }

    func navigateToAppInformation(app: AppModel, account: AccountModel) {
        push(HomeRoute.appInformation(app: app, account: account))
    }

    func navigateToAgeRating(ageRating: AgeRatingDeclarationModel, account: AccountModel) {
        push(HomeRoute.ageRating(ageRating: ageRating, account: account))
    }

    func navigateToManageLocalizations(appInfoId: String, primaryLocale: String, account: AccountModel) {
        push(HomeRoute.manageLocalizations(appInfoId: appInfoId, primaryLocale: primaryLocale, account: account))
    }

    func navigateToArchivedApps(account: AccountModel) {
        push(HomeRoute.archivedApps(account: account))
    }

    func navigateToAppHistory(appId: String, account: AccountModel) {
        push(HomeRoute.appHistory(appId: appId, account: account))
    }

    func navigateToAppPrivacy(appId: String, account: AccountModel) {
        push(HomeRoute.appPrivacy(appId: appId, account: account))
    }

    func navigateToAppAccessibility(appId: String, account: AccountModel) {
        push(HomeRoute.appAccessibility(appId: appId, account: account))
    }

    func navigateToRatingsReviews(appId: String, bundleId: String, appName: String, account: AccountModel) {
        push(HomeRoute.ratingsReviews(appId: appId, bundleId: bundleId, appName: appName, account: account))
    }

    func navigateToReviewDetail(review: CustomerReviewModel, appName: String, account: AccountModel, appId: String? = nil) {
        push(HomeRoute.reviewDetail(review: review, appName: appName, account: account, appId: appId))
    }

    func navigateToAllReviews() {
        push(HomeRoute.allReviews)
    }

    func navigateToTestFlight(appId: String, account: AccountModel) {
        push(HomeRoute.testFlight(appId: appId, account: account))
    }

    func navigateToBetaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel) {
        push(HomeRoute.betaGroupDetail(group: group, appId: appId, account: account))
    }

    func navigateToBetaGroupTesters(group: BetaGroupModel, appId: String, account: AccountModel) {
        push(HomeRoute.betaGroupTesters(group: group, appId: appId, account: account))
    }

    func navigateToPlatformBuildsList(appId: String, platform: String, account: AccountModel) {
        push(HomeRoute.platformBuildsList(appId: appId, platform: platform, account: account))
    }

    func navigateToBuildDetail(build: BuildModel, appId: String, account: AccountModel) {
        push(HomeRoute.buildDetail(build: build, appId: appId, account: account))
    }

    func navigateToUserDetail(user: UserModel, account: AccountModel) {
        push(HomeRoute.userDetail(user: user, account: account))
    }

    func navigateToSubmissions(appId: String, appName: String?, account: AccountModel) {
        push(HomeRoute.submissions(appId: appId, appName: appName, account: account))
    }

    func navigateToReviewSubmissionDetail(submission: ReviewSubmissionModel, account: AccountModel) {
        push(HomeRoute.reviewSubmissionDetail(submission: submission, account: account))
    }

    func navigateToAnalyticsReports(appId: String, appName: String, account: AccountModel) {
        push(HomeRoute.analyticsReports(appId: appId, appName: appName, account: account))
    }

    func navigateToAnalyticsReportDetail(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) {
        push(HomeRoute.analyticsReportDetail(appId: appId, appName: appName, report: report, account: account))
    }

    func navigateToAnalyticsReportFiles(appId: String, appName: String, report: AnalyticsCatalogReport, account: AccountModel) {
        push(HomeRoute.analyticsReportFiles(appId: appId, appName: appName, report: report, account: account))
    }

    func navigateToAppCategoryPicker(
        appInfoId: String,
        primaryCategoryId: String?,
        primarySubcategoryId: String?,
        secondaryCategoryId: String?,
        secondarySubcategoryId: String?,
        account: AccountModel
    ) {
        push(HomeRoute.appCategoryPicker(
            appInfoId: appInfoId,
            primaryCategoryId: primaryCategoryId,
            primarySubcategoryId: primarySubcategoryId,
            secondaryCategoryId: secondaryCategoryId,
            secondarySubcategoryId: secondarySubcategoryId,
            account: account
        ))
    }
}
