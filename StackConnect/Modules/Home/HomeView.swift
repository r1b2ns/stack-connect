import SwiftUI

// MARK: - Factory

struct HomeViewFactory {
    static func build() -> some View {
        HomeEntry()
    }
}

// MARK: - Entry

private struct HomeEntry: View {
    @StateObject private var coordinator = HomeCoordinator()
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        HomeView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct HomeView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator
    @State private var showAssistantSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            buildContent()
                .navigationTitle("StackConnect")
                .navigationDestinations()
        }
    }

    // MARK: - Content

    private func buildContent() -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.uiState.providers, id: \.self) { provider in
                    ProviderCardView(provider: provider)
                        .onTapGesture {
                            coordinator.navigateToAccountsList(provider)
                        }
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            AssistantButton {
                showAssistantSheet = true
            }
        }
        .sheet(isPresented: $showAssistantSheet) {
            AssistantSheetView()
        }
    }
}

// MARK: - Navigation Destinations

private extension View {
    @ViewBuilder
    func navigationDestinations() -> some View {
        self.navigationDestination(for: HomeRoute.self) { route in
            switch route {
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
            case .appDetail(let app, let account):
                AppDetailViewFactory.build(app: app, account: account)
            case .versionList(let appId, let platform, let account):
                VersionListViewFactory.build(appId: appId, platform: platform, account: account)
            case .versionDetail(let version, let account):
                VersionDetailViewFactory.build(version: version, account: account)
            case .buildSelection(let versionId, let appId, let account):
                BuildSelectionViewFactory.build(versionId: versionId, appId: appId, account: account)
            case .screenshotPreview(let versionId, let account):
                ScreenshotPreviewViewFactory.build(versionId: versionId, account: account)
            case .screenshotResolution(let device, let sets):
                ScreenshotResolutionViewFactory.build(device: device, sets: sets)
            case .screenshotPage(let screenshots):
                ScreenshotPageViewFactory.build(screenshots: screenshots)
            case .appReviewInfo(let versionId, let account):
                AppReviewInfoViewFactory.build(versionId: versionId, account: account)
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
            case .appAnalytics(let appId, let account):
                AppAnalyticsViewFactory.build(appId: appId, account: account)
            case .ratingsReviews(let appId, let account):
                RatingsReviewsViewFactory.build(appId: appId, account: account)
            case .reviewDetail(let review, let account):
                ReviewDetailViewFactory.build(review: review, account: account)
            case .testFlight(let appId, let account):
                TestFlightViewFactory.build(appId: appId, account: account)
            case .betaGroupDetail(let group, let appId, let account):
                BetaGroupDetailViewFactory.build(group: group, appId: appId, account: account)
            case .appReview(let appId, let appName, let account):
                AppReviewListViewFactory.build(appId: appId, appName: appName, account: account)
            case .reviewSubmissionDetail(let submission, let account):
                AppReviewDetailViewFactory.build(submission: submission, account: account)
            }
        }
    }
}
