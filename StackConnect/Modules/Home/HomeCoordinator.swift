import SwiftUI

enum HomeRoute: Hashable {
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
    case buildSelection(versionId: String, appId: String, account: AccountModel)
    case screenshotPreview(versionId: String, account: AccountModel)
    case screenshotResolution(device: ScreenshotDeviceType, sets: [ScreenshotSetModel])
    case screenshotPage(screenshots: [ScreenshotModel])
    case appReviewInfo(versionId: String, account: AccountModel)
    case appInformation(app: AppModel, account: AccountModel)
    case ageRating(ageRating: AgeRatingDeclarationModel, account: AccountModel)
    case manageLocalizations(appInfoId: String, primaryLocale: String, account: AccountModel)
    case appCategoryPicker(appInfoId: String, primaryCategoryId: String?, primarySubcategoryId: String?, secondaryCategoryId: String?, secondarySubcategoryId: String?, account: AccountModel)
    case archivedApps(account: AccountModel)
    case appReview(appId: String, appName: String, account: AccountModel)
    case reviewSubmissionDetail(submission: ReviewSubmissionModel, account: AccountModel)
    case appHistory(appId: String, account: AccountModel)
    case appPrivacy(appId: String, account: AccountModel)
    case appAccessibility(appId: String, account: AccountModel)
    case appAnalytics(appId: String, account: AccountModel)
    case ratingsReviews(appId: String, account: AccountModel)
    case reviewDetail(review: CustomerReviewModel, account: AccountModel)
    case testFlight(appId: String, account: AccountModel)
    case betaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel)
}

final class HomeCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()

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

    func navigateToBuildSelection(versionId: String, appId: String, account: AccountModel) {
        path.append(HomeRoute.buildSelection(versionId: versionId, appId: appId, account: account))
    }

    func navigateToScreenshotPreview(versionId: String, account: AccountModel) {
        path.append(HomeRoute.screenshotPreview(versionId: versionId, account: account))
    }

    func navigateToScreenshotResolution(device: ScreenshotDeviceType, sets: [ScreenshotSetModel]) {
        path.append(HomeRoute.screenshotResolution(device: device, sets: sets))
    }

    func navigateToScreenshotPage(screenshots: [ScreenshotModel]) {
        path.append(HomeRoute.screenshotPage(screenshots: screenshots))
    }

    func navigateToAppReviewInfo(versionId: String, account: AccountModel) {
        path.append(HomeRoute.appReviewInfo(versionId: versionId, account: account))
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

    func navigateToAppAnalytics(appId: String, account: AccountModel) {
        path.append(HomeRoute.appAnalytics(appId: appId, account: account))
    }

    func navigateToRatingsReviews(appId: String, account: AccountModel) {
        path.append(HomeRoute.ratingsReviews(appId: appId, account: account))
    }

    func navigateToReviewDetail(review: CustomerReviewModel, account: AccountModel) {
        path.append(HomeRoute.reviewDetail(review: review, account: account))
    }

    func navigateToTestFlight(appId: String, account: AccountModel) {
        path.append(HomeRoute.testFlight(appId: appId, account: account))
    }

    func navigateToBetaGroupDetail(group: BetaGroupModel, appId: String, account: AccountModel) {
        path.append(HomeRoute.betaGroupDetail(group: group, appId: appId, account: account))
    }

    func navigateToAppReview(appId: String, appName: String, account: AccountModel) {
        path.append(HomeRoute.appReview(appId: appId, appName: appName, account: account))
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
