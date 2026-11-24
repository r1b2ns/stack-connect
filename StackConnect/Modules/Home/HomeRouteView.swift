import SwiftUI

// MARK: - Route View

/// The screen of a `HomeRoute`. Single source of truth for the route → factory
/// mapping, used by the compact Home stack, by the split view's detail column
/// stack and as the split view's detail root (`RootSplitView`).
struct HomeRouteView: View {

    let route: HomeRoute

    var body: some View {
        switch route {
        case .settingsAccounts:
            SettingsAccountsViewFactory.build()
        case .license:
            LicenseViewFactory.build()
        case .tipJar:
            TipJarViewFactory.build()
        case .networkAudit:
            NetworkAuditViewFactory.build()
        case .networkAuditEvent(let summary):
            NetworkAuditDetailViewFactory.build(summary: summary)
        case .networkAuditRetention:
            NetworkAuditRetentionViewFactory.build()
        case .accountSettings(let account):
            AccountSettingsViewFactory.build(account: account)
        case .accountManagement(let account):
            AccountManagementViewFactory.build(account: account)
        case .certificatesList(let account):
            CertificatesListViewFactory.build(account: account)
        case .createCertificate(let account):
            CreateCertificateViewFactory.build(account: account)
        case .certificateDetail(let certificate, let account):
            CertificateDetailViewFactory.build(account: account, certificate: certificate)
        case .profilesList(let account):
            ProfilesListViewFactory.build(account: account)
        case .createProfile(let account):
            CreateProfileViewFactory.build(account: account)
        case .profileDetail(let profile, let account):
            ProfileDetailViewFactory.build(account: account, profile: profile)
        case .identifiersList(let account):
            IdentifiersListViewFactory.build(account: account)
        case .identifierDetail(let bundleId, let account):
            IdentifierDetailViewFactory.build(account: account, bundleId: bundleId)
        case .devicesList(let account):
            DevicesListViewFactory.build(account: account)
        case .deviceDetail(let device, let account):
            DeviceDetailViewFactory.build(account: account, device: device)
        case .importDevices(let account):
            ImportDevicesViewFactory.build(account: account)
        case .accountsList(let providerType):
            AccountsListViewFactory.build(providerType: providerType)
        case .appList(let account):
            AppListViewFactory.build(account: account)
        case .firebaseProjectList(let account):
            FirebaseProjectListViewFactory.build(account: account)
        case .firebaseProjectDetail(let project, let account):
            FirebaseProjectDetailViewFactory.build(project: project, account: account)
        case .firebaseAppList(let project, let account):
            FirebaseAppListViewFactory.build(account: account, project: project)
        case .remoteConfig(let project, let account):
            RemoteConfigViewFactory.build(project: project, account: account)
        case .analyticsDashboard(let project, let account):
            AnalyticsDashboardViewFactory.build(project: project, account: account)
        case .messaging(let project, let account):
            MessagingViewFactory.build(project: project, account: account)
        case .googlePlayAppList(let account):
            GooglePlayAppListViewFactory.build(account: account)
        case .googlePlayAppDetail(let app, let account):
            GooglePlayAppDetailViewFactory.build(app: app, account: account)
        case .googlePlayStoreListings(let app, let account):
            GooglePlayStoreListingsViewFactory.build(app: app, account: account)
        case .googlePlayStoreListingDetail(let listing, let isDefaultLanguage):
            GooglePlayStoreListingDetailViewFactory.build(listing: listing, isDefaultLanguage: isDefaultLanguage)
        case .googlePlayTracks(let app, let account):
            GooglePlayTracksViewFactory.build(app: app, account: account)
        case .googlePlayReleaseDetail(let app, let account, let track, let release):
            GooglePlayReleaseDetailViewFactory.build(app: app, account: account, track: track, release: release)
        case .googlePlayAppInfo(let app, let account):
            GooglePlayAppInfoViewFactory.build(app: app, account: account)
        case .googlePlayUserDetail(let user, let account):
            GooglePlayUserDetailViewFactory.build(user: user, account: account)
        case .appDetail(let app, let account):
            AppDetailViewFactory.build(app: app, account: account)
        case .versionList(let appId, let platform, let account):
            VersionListViewFactory.build(appId: appId, platform: platform, account: account)
        case .versionDetail(let version, let account):
            VersionDetailViewFactory.build(version: version, account: account)
        case .screenshotPreview(let versionId, let localizationId, let platform, let appStoreState, let account):
            ScreenshotPreviewViewFactory.build(versionId: versionId, account: account, localizationId: localizationId, platform: platform, appStoreState: appStoreState)
        case .screenshotResolution(let device, let sets, let account, let appStoreState):
            ScreenshotResolutionViewFactory.build(device: device, sets: sets, account: account, appStoreState: appStoreState)
        case .screenshotGrid(let screenshots, let account, let appStoreState):
            ScreenshotGridViewFactory.build(screenshots: screenshots, account: account, appStoreState: appStoreState)
        case .screenshotPage(let screenshots, let startIndex, let account, let appStoreState):
            ScreenshotPageViewFactory.build(screenshots: screenshots, startIndex: startIndex, account: account, appStoreState: appStoreState)
        case .appReviewInfo(let versionId, let account):
            AppReviewInfoViewFactory.build(versionId: versionId, account: account)
        case .betaAppReviewInfo(let appId, let account):
            BetaAppReviewInfoViewFactory.build(appId: appId, account: account)
        case .appInformation(let app, let account):
            AppInformationViewFactory.build(app: app, account: account)
        case .ageRating(let ageRating, let account):
            AgeRatingViewFactory.build(ageRating: ageRating, account: account)
        case .manageLocalizations(let appInfoId, let primaryLocale, let account):
            ManageLocalizationsViewFactory.build(appInfoId: appInfoId, primaryLocale: primaryLocale, account: account)
        case .appCategoryPicker(let appInfoId, let primaryCategoryId, let primarySubcategoryId, let secondaryCategoryId, let secondarySubcategoryId, let account):
            AppCategoryPickerViewFactory.build(appInfoId: appInfoId, currentCategoryId: primaryCategoryId, currentSubcategoryId: primarySubcategoryId, currentSecondaryCategoryId: secondaryCategoryId, currentSecondarySubcategoryId: secondarySubcategoryId, account: account)
        case .archivedApps(let account):
            ArchivedAppsViewFactory.build(account: account)
        case .appHistory(let appId, let account):
            AppHistoryViewFactory.build(appId: appId, account: account)
        case .appPrivacy(let appId, let account):
            AppPrivacyViewFactory.build(appId: appId, account: account)
        case .appAccessibility(let appId, let account):
            AppAccessibilityViewFactory.build(appId: appId, account: account)
        case .ratingsReviews(let appId, let bundleId, let appName, let account):
            RatingsReviewsViewFactory.build(appId: appId, bundleId: bundleId, appName: appName, account: account)
        case .reviewDetail(let review, let appName, let account, let appId):
            ReviewDetailViewFactory.build(review: review, appName: appName, account: account, appId: appId)
        case .allReviews:
            AllReviewsViewFactory.build()
        case .testFlight(let appId, let account):
            TestFlightViewFactory.build(appId: appId, account: account)
        case .betaGroupDetail(let group, let appId, let account):
            BetaGroupDetailViewFactory.build(group: group, appId: appId, account: account)
        case .betaGroupTesters(let group, let appId, let account):
            BetaGroupTestersViewFactory.build(group: group, appId: appId, account: account)
        case .platformBuildsList(let appId, let platform, let account):
            PlatformBuildsViewFactory.build(appId: appId, platform: platform, account: account)
        case .buildDetail(let build, let appId, let account):
            BuildDetailViewFactory.build(build: build, appId: appId, account: account)
        case .submissions(let appId, let appName, let account):
            SubmissionsViewFactory.build(appId: appId, appName: appName, account: account)
        case .reviewSubmissionDetail(let submission, let account):
            AppReviewDetailViewFactory.build(submission: submission, account: account)
        case .userDetail(let user, let account):
            UserDetailViewFactory.build(user: user, account: account)
        case .analyticsReports(let appId, let appName, let account):
            AnalyticsReportsViewFactory.build(appId: appId, appName: appName, account: account)
        case .analyticsReportDetail(let appId, let appName, let report, let account):
            AnalyticsReportDetailViewFactory.build(appId: appId, appName: appName, report: report, account: account)
        case .analyticsReportFiles(let appId, let appName, let report, let account):
            AnalyticsReportFilesViewFactory.build(appId: appId, appName: appName, report: report, account: account)
        }
    }
}

// MARK: - Navigation Destinations

extension View {
    /// Registers `HomeRouteView` for every `HomeRoute` pushed on the enclosing
    /// `NavigationStack`.
    ///
    /// - Parameter coordinator: injected into every destination when set. A
    ///   stack inside a `NavigationSplitView` column does not hand the
    ///   environment objects set on it down to its pushed screens, so the split
    ///   view passes its detail coordinator explicitly.
    @ViewBuilder
    func homeNavigationDestinations(coordinator: HomeCoordinator? = nil) -> some View {
        if let coordinator {
            navigationDestination(for: HomeRoute.self) { route in
                HomeRouteView(route: route)
                    .environmentObject(coordinator)
            }
        } else {
            navigationDestination(for: HomeRoute.self) { route in
                HomeRouteView(route: route)
            }
        }
    }
}
