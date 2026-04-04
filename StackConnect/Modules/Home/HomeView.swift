import SwiftUI

// MARK: - Factory

@MainActor
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

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            List {
                buildAccountsSection()
                buildPendingReviewSection()
            }
            .navigationTitle("StackConnect")
            .navigationDestinations()
            .task { await viewModel.loadPendingReviewApps() }
        }
    }

    // MARK: - Accounts Section

    private func buildAccountsSection() -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.uiState.providers, id: \.self) { provider in
                    ProviderCardView(provider: provider)
                        .onTapGesture {
                            coordinator.navigateToAccountsList(provider)
                        }
                }

                buildSettingsCard()
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
        .listRowBackground(Color.clear)
    }

    private func buildSettingsCard() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40))
                .foregroundStyle(.gray)

            Text(String(localized: "Settings"))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            coordinator.navigateToSettings()
        }
    }

    // MARK: - Pending Review Section

    @ViewBuilder
    private func buildPendingReviewSection() -> some View {
        if !viewModel.uiState.pendingReviewApps.isEmpty {
            Section {
                ForEach(viewModel.uiState.pendingReviewApps) { app in
                    Button {
                        coordinator.navigateToAppDetail(app, account: accountForApp(app))
                    } label: {
                        buildPendingAppRow(app)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                HStack {
                    Image(systemName: "apple.logo")
                    Text("App Review")
                    Spacer()
                    if viewModel.uiState.isLoadingPending {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
    }

    private func buildPendingAppRow(_ app: AppModel) -> some View {
        HStack(spacing: 12) {
            buildAppIcon(url: app.iconUrl.flatMap { URL(string: $0) })

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let state = app.appStoreState {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(state.color))
                            .frame(width: 6, height: 6)

                        Text(state.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let version = app.versionString {
                            Text("(\(version))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildAppIcon(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        appIconPlaceholder
                    }
                }
            } else {
                appIconPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var appIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Image(systemName: "app.fill")
                    .foregroundStyle(.gray.opacity(0.4))
            )
    }

    private func statusColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }

    private func accountForApp(_ app: AppModel) -> AccountModel {
        AccountModel(
            id: app.accountId,
            name: "",
            providerType: .apple
        )
    }
}

// MARK: - Navigation Destinations

private extension View {
    @ViewBuilder
    func navigationDestinations() -> some View {
        self.navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .settings:
                SettingsViewFactory.build()
            case .settingsAccounts:
                SettingsAccountsViewFactory.build()
            case .accountSettings(let account):
                AccountSettingsViewFactory.build(account: account)
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
            case .ratingsReviews(let appId, let bundleId, let account):
                RatingsReviewsViewFactory.build(appId: appId, bundleId: bundleId, account: account)
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
