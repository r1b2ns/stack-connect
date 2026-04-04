import SwiftUI

// MARK: - Factory

@MainActor
struct AppDetailViewFactory {
    static func build(app: AppModel, account: AccountModel) -> some View {
        AppDetailEntry(app: app, account: account)
    }
}

// MARK: - Entry

private struct AppDetailEntry: View {
    let app: AppModel
    let account: AccountModel

    @StateObject private var coordinator = AppDetailCoordinator()
    @StateObject private var viewModel: AppDetailViewModel

    init(app: AppModel, account: AccountModel) {
        self.app = app
        self.account = account
        _viewModel = StateObject(wrappedValue: AppDetailViewModel(app: app, account: account))
    }

    var body: some View {
        AppDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AppDetailView<ViewModel: AppDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    @State private var showPermissionDenied = false
    @State private var permissionDeniedMessage = ""

    private var account: AccountModel { viewModel.uiState.account }

    private var isAppEditable: Bool {
        guard let state = viewModel.uiState.app.appStoreState else { return true }
        return [.prepareForSubmission, .rejected, .readyForReview, .waitingForReview, .waitingForExportCompliance].contains(state)
    }

    var body: some View {
        List {
            buildHeaderSection()
            buildPlatformSections()
            buildGeneralSection()
            buildAppStoreSection()
            buildAnalyticsSection()
            buildTestFlightSection()
        }
        .foregroundStyle(.primary)
        .navigationTitle(viewModel.uiState.app.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buildToolbar() }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $viewModel.uiState.showCreatePlatform) {
            CreatePlatformSheet(viewModel: viewModel)
        }
        .alert(
            viewModel.uiState.confirmAction?.title ?? "",
            isPresented: Binding(
                get: { viewModel.uiState.confirmAction != nil },
                set: { if !$0 { viewModel.uiState.confirmAction = nil } }
            )
        ) {
            if let action = viewModel.uiState.confirmAction {
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await performAction(action) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.uiState.confirmAction = nil
                }
            }
        } message: {
            if let action = viewModel.uiState.confirmAction {
                Text(action.message)
            }
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.uiState.actionError != nil },
                set: { if !$0 { viewModel.uiState.actionError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.uiState.actionError = nil
            }
        } message: {
            if let error = viewModel.uiState.actionError {
                Text(error)
            }
        }
        .toast(message: $viewModel.uiState.toastMessage)
        .alert(
            String(localized: "Permission Denied"),
            isPresented: $showPermissionDenied
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(permissionDeniedMessage)
        }
    }

    private func denyPermission(_ message: String) {
        permissionDeniedMessage = message
        showPermissionDenied = true
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 16) {
                buildAppIcon(url: viewModel.uiState.app.iconUrl.flatMap { URL(string: $0) }, size: 64, radius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.uiState.app.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(viewModel.uiState.app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let state = viewModel.uiState.app.appStoreState {
                        buildStatusBadge(state: state, version: viewModel.uiState.app.versionString)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Platform Sections

    @ViewBuilder
    private func buildPlatformSections() -> some View {
        if account.canView(.version) {
            ForEach(viewModel.uiState.platformSections) { section in
                buildPlatformSection(section)
            }
        }
    }

    @ViewBuilder
    private func buildPlatformSection(_ section: PlatformSection) -> some View {
        let versions: [AppStoreVersionModel] = section.versions
        Section {
            ForEach(versions) { version in
                Button {
                    homeCoordinator.navigateToVersionDetail(version, account: viewModel.uiState.account)
                } label: {
                    buildVersionRow(version)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    buildSwipeActions(for: version)
                }
            }

            Button {
                homeCoordinator.navigateToVersionList(
                    appId: viewModel.uiState.app.id,
                    platform: section.platform,
                    account: viewModel.uiState.account
                )
            } label: {
                Text("See All")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.accent)
        } header: {
            Label(section.platform.displayName, systemImage: section.platform.icon)
        }
    }

    private func buildVersionRow(_ version: AppStoreVersionModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.versionString ?? "–")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let state = version.appStoreState {
                    buildStatusBadge(state: state, version: nil)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func buildSwipeActions(for version: AppStoreVersionModel) -> some View {
        switch version.appStoreState {
        case .prepareForSubmission:
            if account.canEdit(.version) {
                Button {
                    viewModel.uiState.confirmAction = .submitForReview(version)
                } label: {
                    Label(String(localized: "Submit"), systemImage: "paperplane.fill")
                }
                .tint(.blue)
            }

            if account.canDelete(.version) {
                Button(role: .destructive) {
                    viewModel.uiState.confirmAction = .delete(version)
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }

        case .pendingDeveloperRelease:
            if account.canEdit(.version) {
                Button {
                    viewModel.uiState.confirmAction = .release(version)
                } label: {
                    Label(String(localized: "Release"), systemImage: "arrow.up.circle.fill")
                }
                .tint(.green)
            }

            if account.canDelete(.version) {
                Button(role: .destructive) {
                    viewModel.uiState.confirmAction = .reject(version)
                } label: {
                    Label(String(localized: "Reject"), systemImage: "xmark.circle.fill")
                }
            }

        case .inReview, .waitingForReview:
            if account.canEdit(.version) {
                Button(role: .destructive) {
                    viewModel.uiState.confirmAction = .cancelReview(version)
                } label: {
                    Label(String(localized: "Cancel"), systemImage: "xmark.circle.fill")
                }
            }

        default:
            EmptyView()
        }
    }

    private func performAction(_ action: VersionAction) async {
        switch action {
        case .submitForReview(let version):
            await viewModel.submitForReview(version: version)
        case .cancelReview(let version):
            await viewModel.cancelReview(version: version)
        case .release(let version):
            await viewModel.releaseVersion(version)
        case .reject(let version):
            await viewModel.rejectVersion(version)
        case .delete(let version):
            await viewModel.deleteVersion(id: version.id)
        }
    }

    // MARK: - General

    private func buildGeneralSection() -> some View {
        Section {
            Button {
                guard account.canEdit(.apps) else {
                    denyPermission(String(localized: "You don't have permission to edit app information."))
                    return
                }
                homeCoordinator.navigateToAppInformation(
                    app: viewModel.uiState.app,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "info.circle.fill", color: .blue, title: String(localized: "App Information"))
            }

            Button {
                guard account.canEdit(.apps) else {
                    denyPermission(String(localized: "You don't have permission to access App Review."))
                    return
                }
                homeCoordinator.navigateToAppReview(
                    appId: viewModel.uiState.app.id,
                    appName: viewModel.uiState.app.name,
                    account: account
                )
            } label: {
                buildMenuRow(
                    icon: "checkmark.shield.fill",
                    color: .green,
                    title: String(localized: "App Review"),
                    badge: viewModel.uiState.hasReviewIssues ? .exclamation : nil
                )
            }
            Button {
                guard account.canEdit(.apps) else {
                    denyPermission(String(localized: "You don't have permission to access app history."))
                    return
                }
                homeCoordinator.navigateToAppHistory(
                    appId: viewModel.uiState.app.id,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "clock.fill", color: .orange, title: String(localized: "History"))
            }
        } header: {
            Text("General")
        }
    }

    // MARK: - App Store

    private func buildAppStoreSection() -> some View {
        Section {
            Button {
                guard account.canEdit(.apps) else {
                    denyPermission(String(localized: "You don't have permission to edit app privacy."))
                    return
                }
                homeCoordinator.navigateToAppPrivacy(
                    appId: viewModel.uiState.app.id,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "hand.raised.fill", color: .blue, title: String(localized: "App Privacy"))
            }
            Button {
                guard account.canEdit(.apps) else {
                    denyPermission(String(localized: "You don't have permission to edit app accessibility."))
                    return
                }
                homeCoordinator.navigateToAppAccessibility(
                    appId: viewModel.uiState.app.id,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "accessibility", color: .purple, title: String(localized: "App Accessibility"))
            }
            Button {
                guard account.canView(.review) else {
                    denyPermission(String(localized: "You don't have permission to view ratings and reviews."))
                    return
                }
                homeCoordinator.navigateToRatingsReviews(
                    appId: viewModel.uiState.app.id,
                    bundleId: viewModel.uiState.app.bundleId,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "star.fill", color: .yellow, title: String(localized: "Ratings and Reviews"))
            }
        } header: {
            Text("App Store")
        }
    }

    // MARK: - Analytics

    private func buildAnalyticsSection() -> some View {
        Section {
            Button {
                guard account.canView(.analytics) else {
                    denyPermission(String(localized: "You don't have permission to view analytics."))
                    return
                }
                homeCoordinator.navigateToAppAnalytics(
                    appId: viewModel.uiState.app.id,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "chart.bar.fill", color: .purple, title: String(localized: "Analytics"))
            }
        }
    }

    // MARK: - TestFlight

    private func buildTestFlightSection() -> some View {
        Section {
            Button {
                guard account.canView(.testFlight) else {
                    denyPermission(String(localized: "You don't have permission to view TestFlight."))
                    return
                }
                homeCoordinator.navigateToTestFlight(
                    appId: viewModel.uiState.app.id,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "airplane", color: .cyan, title: String(localized: "TestFlight"))
            }
        }
    }

    // MARK: - Reusable Components

    enum MenuRowBadge {
        case exclamation
    }

    private func buildMenuRow(icon: String, color: Color, title: String, badge: MenuRowBadge? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.body)

            Spacer()

            if case .exclamation = badge {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.body)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildStatusBadge(state: AppStoreState, version: String?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(state.color))
                .frame(width: 6, height: 6)

            Text(state.displayName)
                .font(.caption)
                .fontWeight(.medium)

            if let version {
                Text("(\(version))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
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

    private func buildAppIcon(url: URL?, size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        appIconPlaceholder(size: size, radius: radius)
                    case .empty:
                        ProgressView().frame(width: size, height: size)
                    @unknown default:
                        appIconPlaceholder(size: size, radius: radius)
                    }
                }
            } else {
                appIconPlaceholder(size: size, radius: radius)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private func appIconPlaceholder(size: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.blue.opacity(0.15))
            .overlay {
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .font(size > 50 ? .title : .title3)
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if account.canAdd(.version) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.uiState.showCreatePlatform = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                Task { await viewModel.toggleFavorite() }
            } label: {
                Image(systemName: viewModel.uiState.app.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(viewModel.uiState.app.isFavorite ? .yellow : .secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.toggleArchive() }
            } label: {
                Image(systemName: viewModel.uiState.app.isArchived ? "archivebox.fill" : "archivebox")
                    .foregroundStyle(viewModel.uiState.app.isArchived ? .orange : .secondary)
            }
        }
    }
}

// MARK: - Create Platform Sheet

struct CreatePlatformSheet<ViewModel: AppDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AppPlatform.allCases) { platform in
                        Toggle(isOn: Binding(
                            get: { viewModel.uiState.selectedPlatforms.contains(platform) },
                            set: { isOn in
                                if isOn {
                                    viewModel.uiState.selectedPlatforms.insert(platform)
                                } else {
                                    viewModel.uiState.selectedPlatforms.remove(platform)
                                }
                            }
                        )) {
                            Label(platform.displayName, systemImage: platform.icon)
                        }
                    }
                } header: {
                    Text("Platforms")
                }

                Section {
                    TextField(
                        String(localized: "Version"),
                        text: $viewModel.uiState.newVersionString
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                } header: {
                    Text("Version")
                }

                if let error = viewModel.uiState.createError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Create Platform"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        viewModel.uiState.showCreatePlatform = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.uiState.isCreating {
                        ProgressView()
                    } else {
                        Button(String(localized: "Add")) {
                            Task { await viewModel.createVersions() }
                        }
                        .disabled(viewModel.uiState.selectedPlatforms.isEmpty)
                    }
                }
            }
            .disabled(viewModel.uiState.isCreating)
        }
    }
}
