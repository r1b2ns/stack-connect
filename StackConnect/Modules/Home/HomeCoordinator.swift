import SwiftUI

enum HomeRoute: Hashable {
    case settings
    case settingsAccounts
    case license
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
    case submissions(appId: String, appName: String?, platform: AppPlatform?, account: AccountModel)
    case reviewSubmissionDetail(submission: ReviewSubmissionModel, account: AccountModel)
    case appHistory(appId: String, account: AccountModel)
    case appPrivacy(appId: String, account: AccountModel)
    case appAccessibility(appId: String, account: AccountModel)
    case ratingsReviews(appId: String, bundleId: String, appName: String, account: AccountModel)
    case reviewDetail(review: CustomerReviewModel, appName: String, account: AccountModel)
    case allReviews
    case testFlight(appId: String, account: AccountModel)
    case betaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel)
    case betaGroupTesters(group: BetaGroupModel, appId: String, account: AccountModel)
    case platformBuildsList(appId: String, platform: String, account: AccountModel)
    case buildDetail(build: BuildModel, appId: String, account: AccountModel)
    case userDetail(user: UserModel, account: AccountModel)
}

final class HomeCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()

    func navigateToSettings() {
        path.append(HomeRoute.settings)
    }

    func navigateToSettingsAccounts() {
        path.append(HomeRoute.settingsAccounts)
    }

    func navigateToLicense() {
        path.append(HomeRoute.license)
    }

    func navigateToAccountSettings(_ account: AccountModel) {
        path.append(HomeRoute.accountSettings(account))
    }

    func navigateToAccountManagement(_ account: AccountModel) {
        path.append(HomeRoute.accountManagement(account))
    }

    func navigateToCertificatesList(_ account: AccountModel) {
        path.append(HomeRoute.certificatesList(account))
    }

    func navigateToCertificateDetail(certificate: CertificateModel, account: AccountModel) {
        path.append(HomeRoute.certificateDetail(certificate: certificate, account: account))
    }

    func navigateToCreateCertificate(_ account: AccountModel) {
        path.append(HomeRoute.createCertificate(account))
    }

    func navigateToProfilesList(_ account: AccountModel) {
        path.append(HomeRoute.profilesList(account))
    }

    func navigateToCreateProfile(_ account: AccountModel) {
        path.append(HomeRoute.createProfile(account))
    }

    func navigateToProfileDetail(profile: ProvisioningProfileModel, account: AccountModel) {
        path.append(HomeRoute.profileDetail(profile: profile, account: account))
    }

    func navigateToIdentifiersList(_ account: AccountModel) {
        path.append(HomeRoute.identifiersList(account))
    }

    func navigateToIdentifierDetail(bundleId: BundleIdentifierModel, account: AccountModel) {
        path.append(HomeRoute.identifierDetail(bundleId: bundleId, account: account))
    }

    func navigateToDevicesList(_ account: AccountModel) {
        path.append(HomeRoute.devicesList(account))
    }

    func navigateToDeviceDetail(device: DeviceModel, account: AccountModel) {
        path.append(HomeRoute.deviceDetail(device: device, account: account))
    }

    func navigateToImportDevices(_ account: AccountModel) {
        path.append(HomeRoute.importDevices(account))
    }

    func navigateToAccountsList(_ providerType: ProviderType) {
        path.append(HomeRoute.accountsList(providerType))
    }

    func navigateToAppList(_ account: AccountModel) {
        path.append(HomeRoute.appList(account))
    }

    func navigateToFirebaseProjectList(_ account: AccountModel) {
        path.append(HomeRoute.firebaseProjectList(account))
    }

    func navigateToFirebaseProjectDetail(project: FirebaseProjectModel, account: AccountModel) {
        path.append(HomeRoute.firebaseProjectDetail(project: project, account: account))
    }

    func navigateToFirebaseAppList(project: FirebaseProjectModel, account: AccountModel) {
        path.append(HomeRoute.firebaseAppList(project: project, account: account))
    }

    func navigateToRemoteConfig(project: FirebaseProjectModel, account: AccountModel) {
        path.append(HomeRoute.remoteConfig(project: project, account: account))
    }

    func navigateToAnalyticsDashboard(project: FirebaseProjectModel, account: AccountModel) {
        path.append(HomeRoute.analyticsDashboard(project: project, account: account))
    }

    func navigateToMessaging(project: FirebaseProjectModel, account: AccountModel) {
        path.append(HomeRoute.messaging(project: project, account: account))
    }

    func navigateToGooglePlayAppList(_ account: AccountModel) {
        path.append(HomeRoute.googlePlayAppList(account))
    }

    func navigateToAppDetail(_ app: AppModel, account: AccountModel) {
        path.append(HomeRoute.appDetail(app: app, account: account))
    }

    func navigateToVersionList(appId: String, platform: AppPlatform, account: AccountModel) {
        path.append(HomeRoute.versionList(appId: appId, platform: platform, account: account))
    }

    func navigateToVersionDetail(_ version: AppStoreVersionModel, account: AccountModel) {
        path.append(HomeRoute.versionDetail(version: version, account: account))
    }

    func navigateToScreenshotPreview(versionId: String, account: AccountModel, localizationId: String? = nil, platform: AppPlatform? = nil, appStoreState: AppStoreState? = nil) {
        path.append(HomeRoute.screenshotPreview(versionId: versionId, localizationId: localizationId, platform: platform, appStoreState: appStoreState, account: account))
    }

    func navigateToScreenshotResolution(device: ScreenshotDeviceType, sets: [ScreenshotSetModel], account: AccountModel, appStoreState: AppStoreState?) {
        path.append(HomeRoute.screenshotResolution(device: device, sets: sets, account: account, appStoreState: appStoreState))
    }

    func navigateToScreenshotGrid(screenshots: [ScreenshotModel], account: AccountModel, appStoreState: AppStoreState?) {
        path.append(HomeRoute.screenshotGrid(screenshots: screenshots, account: account, appStoreState: appStoreState))
    }

    func navigateToScreenshotPage(screenshots: [ScreenshotModel], startIndex: Int = 0, account: AccountModel, appStoreState: AppStoreState?) {
        path.append(HomeRoute.screenshotPage(screenshots: screenshots, startIndex: startIndex, account: account, appStoreState: appStoreState))
    }

    func navigateToAppReviewInfo(versionId: String, account: AccountModel) {
        path.append(HomeRoute.appReviewInfo(versionId: versionId, account: account))
    }

    func navigateToBetaAppReviewInfo(appId: String, account: AccountModel) {
        path.append(HomeRoute.betaAppReviewInfo(appId: appId, account: account))
    }

    func navigateToAppInformation(app: AppModel, account: AccountModel) {
        path.append(HomeRoute.appInformation(app: app, account: account))
    }

    func navigateToAgeRating(ageRating: AgeRatingDeclarationModel, account: AccountModel) {
        path.append(HomeRoute.ageRating(ageRating: ageRating, account: account))
    }

    func navigateToManageLocalizations(appInfoId: String, primaryLocale: String, account: AccountModel) {
        path.append(HomeRoute.manageLocalizations(appInfoId: appInfoId, primaryLocale: primaryLocale, account: account))
    }

    func navigateToArchivedApps(account: AccountModel) {
        path.append(HomeRoute.archivedApps(account: account))
    }

    func navigateToAppHistory(appId: String, account: AccountModel) {
        path.append(HomeRoute.appHistory(appId: appId, account: account))
    }

    func navigateToAppPrivacy(appId: String, account: AccountModel) {
        path.append(HomeRoute.appPrivacy(appId: appId, account: account))
    }

    func navigateToAppAccessibility(appId: String, account: AccountModel) {
        path.append(HomeRoute.appAccessibility(appId: appId, account: account))
    }

    func navigateToRatingsReviews(appId: String, bundleId: String, appName: String, account: AccountModel) {
        path.append(HomeRoute.ratingsReviews(appId: appId, bundleId: bundleId, appName: appName, account: account))
    }

    func navigateToReviewDetail(review: CustomerReviewModel, appName: String, account: AccountModel) {
        path.append(HomeRoute.reviewDetail(review: review, appName: appName, account: account))
    }

    func navigateToAllReviews() {
        path.append(HomeRoute.allReviews)
    }

    func navigateToTestFlight(appId: String, account: AccountModel) {
        path.append(HomeRoute.testFlight(appId: appId, account: account))
    }

    func navigateToBetaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel) {
        path.append(HomeRoute.betaGroupDetail(group: group, appId: appId, account: account))
    }

    func navigateToBetaGroupTesters(group: BetaGroupModel, appId: String, account: AccountModel) {
        path.append(HomeRoute.betaGroupTesters(group: group, appId: appId, account: account))
    }

    func navigateToPlatformBuildsList(appId: String, platform: String, account: AccountModel) {
        path.append(HomeRoute.platformBuildsList(appId: appId, platform: platform, account: account))
    }

    func navigateToBuildDetail(build: BuildModel, appId: String, account: AccountModel) {
        path.append(HomeRoute.buildDetail(build: build, appId: appId, account: account))
    }

    func navigateToUserDetail(user: UserModel, account: AccountModel) {
        path.append(HomeRoute.userDetail(user: user, account: account))
    }

    func navigateToSubmissions(appId: String, appName: String?, platform: AppPlatform?, account: AccountModel) {
        path.append(HomeRoute.submissions(appId: appId, appName: appName, platform: platform, account: account))
    }

    func navigateToReviewSubmissionDetail(submission: ReviewSubmissionModel, account: AccountModel) {
        path.append(HomeRoute.reviewSubmissionDetail(submission: submission, account: account))
    }

    func navigateToAppCategoryPicker(
        appInfoId: String,
        primaryCategoryId: String?,
        primarySubcategoryId: String?,
        secondaryCategoryId: String?,
        secondarySubcategoryId: String?,
        account: AccountModel
    ) {
        path.append(HomeRoute.appCategoryPicker(
            appInfoId: appInfoId,
            primaryCategoryId: primaryCategoryId,
            primarySubcategoryId: primarySubcategoryId,
            secondaryCategoryId: secondaryCategoryId,
            secondarySubcategoryId: secondarySubcategoryId,
            account: account
        ))
    }
}
