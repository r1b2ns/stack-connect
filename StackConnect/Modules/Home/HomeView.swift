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
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onReceive(DeepLinkRouter.shared.$pending.compactMap { $0 }) { url in
                handleDeepLink(url)
                DeepLinkRouter.shared.pending = nil
            }
    }

    /// Routes deep links (scheme `stackconnect`) from widgets and local
    /// notifications into the Home navigation stack.
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .home:
            coordinator.path = NavigationPath()
        case .reviews:
            coordinator.path = NavigationPath()
            coordinator.navigateToAllReviews()
        case let .app(accountId, appId):
            Task { await openAppDetail(accountId: accountId, appId: appId) }
        case let .review(accountId, appId, reviewId):
            Task { await openReviewDetail(accountId: accountId, appId: appId, reviewId: reviewId) }
        case let .reimport(accountId):
            Task { await openReimport(accountId: accountId) }
        }
    }

    @MainActor
    private func openReimport(accountId: String) async {
        guard let storage = SwiftDataStorable.shared,
              let account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId) else { return }
        coordinator.path = NavigationPath()
        coordinator.navigateToAccountsList(account.providerType)
        ReimportRouter.shared.request(accountId: accountId, providerType: account.providerType)
    }

    @MainActor
    private func openAppDetail(accountId: String, appId: String) async {
        guard let storage = SwiftDataStorable.shared,
              var account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId),
              let app: AppModel = try? await storage.fetch(AppModel.self, id: "\(accountId).\(appId)") else { return }
        account.fillMissingRules()
        coordinator.path = NavigationPath()
        coordinator.navigateToAppDetail(app, account: account)
    }

    @MainActor
    private func openReviewDetail(accountId: String, appId: String, reviewId: String) async {
        guard let storage = SwiftDataStorable.shared,
              var account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId),
              let app: AppModel = try? await storage.fetch(AppModel.self, id: "\(accountId).\(appId)"),
              let review: CustomerReviewModel = try? await storage.fetch(CustomerReviewModel.self, id: "review.\(appId).\(reviewId)") else { return }
        account.fillMissingRules()
        coordinator.path = NavigationPath()
        coordinator.navigateToReviewDetail(review: review, appName: app.name, account: account)
    }
}

// MARK: - View

struct HomeView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator
    @State private var isCustomizingWidgets = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            List {
                buildSyncBanner()
                buildAccountsSection()
                buildWidgetsSection()
            }
            .navigationTitle("StackConnect")
            .navigationDestinations()
            .toolbar { buildToolbar() }
            .refreshable { await viewModel.refresh() }
            .task {
                viewModel.triggerSync()
                await viewModel.loadDashboard()
            }
            .sheet(isPresented: $isCustomizingWidgets) {
                CustomizeWidgetsView(viewModel: viewModel)
            }
            .alert(
                String(localized: "Account Expired"),
                isPresented: $viewModel.uiState.showExpiredAlert,
                presenting: viewModel.uiState.expiredAccount
            ) { account in
                Button(String(localized: "Re-import File")) {
                    DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { account in
                Text("The account \"\(account.name)\" has expired. Re-import its file to keep using it, or it will stay locked.")
            }
            .alert(
                String(localized: "Account Expiring Soon"),
                isPresented: $viewModel.uiState.showExpiringSoonAlert,
                presenting: viewModel.uiState.expiringSoonAccount
            ) { account in
                Button(String(localized: "Re-import File")) {
                    DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
                }
                Button(String(localized: "OK"), role: .cancel) {}
            } message: { account in
                if let expirationDate = account.expirationDate {
                    Text("The account \"\(account.name)\" will expire on \(expirationDate.formatted(date: .abbreviated, time: .shortened)). Request a new file from the administrator before then.")
                } else {
                    Text("The account \"\(account.name)\" will expire soon. Request a new file from the administrator.")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isCustomizingWidgets = true
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .accessibilityLabel(String(localized: "Customize Widgets"))
        }
    }

    // MARK: - Sync Banner

    @ViewBuilder
    private func buildSyncBanner() -> some View {
        if viewModel.uiState.syncState.isSyncing {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.75)

                Text(syncBannerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
        }
    }

    private var syncBannerText: String {
        let count = viewModel.uiState.syncState.accountsInProgress.count
        if count > 0 {
            return String(localized: "Syncing \(count) account(s)…")
        }
        return String(localized: "Syncing…")
    }

    // MARK: - Widgets Section

    @ViewBuilder
    private func buildWidgetsSection() -> some View {
        if viewModel.uiState.widgets.isEmpty {
            Section {
                buildWidgetsEmptyState()
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(viewModel.uiState.widgets, id: \.id) { widget in
                    HomeWidgetContainerView(widget: widget)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func buildWidgetsEmptyState() -> some View {
        Button {
            isCustomizingWidgets = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No widgets yet"))
                    .font(.headline)
                Text(String(localized: "Add widgets to keep an eye on your apps right from here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "Add Widgets"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            case .license:
                LicenseViewFactory.build()
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
            case .appDetail(let app, let account):
                AppDetailViewFactory.build(app: app, account: account)
            case .versionList(let appId, let platform, let account):
                VersionListViewFactory.build(appId: appId, platform: platform, account: account)
            case .versionDetail(let version, let account):
                VersionDetailViewFactory.build(version: version, account: account)
            case .buildSelection(let versionId, let appId, let account):
                BuildSelectionViewFactory.build(versionId: versionId, appId: appId, account: account)
            case .screenshotPreview(let versionId, let localizationId, let account):
                ScreenshotPreviewViewFactory.build(versionId: versionId, account: account, localizationId: localizationId)
            case .screenshotResolution(let device, let sets):
                ScreenshotResolutionViewFactory.build(device: device, sets: sets)
            case .screenshotPage(let screenshots):
                ScreenshotPageViewFactory.build(screenshots: screenshots)
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
            case .appAnalytics(let appId, let account):
                AppAnalyticsViewFactory.build(appId: appId, account: account)
            case .ratingsReviews(let appId, let bundleId, let appName, let account):
                RatingsReviewsViewFactory.build(appId: appId, bundleId: bundleId, appName: appName, account: account)
            case .reviewDetail(let review, let appName, let account):
                ReviewDetailViewFactory.build(review: review, appName: appName, account: account)
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
            case .appReview(let appId, let appName, let account):
                AppReviewListViewFactory.build(appId: appId, appName: appName, account: account)
            case .reviewSubmissionDetail(let submission, let account):
                AppReviewDetailViewFactory.build(submission: submission, account: account)
            }
        }
    }
}
