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
        return [.prepareForSubmission, .rejected, .developerRejected, .readyForReview, .waitingForReview, .waitingForExportCompliance].contains(state)
    }

    /// True when the header should hide its single app icon and each platform
    /// section should show its own real icon instead. Only triggers when the
    /// platform sections are actually visible (gated behind `.version` view
    /// permission) and the app ships more than one platform.
    private var showsPerPlatformIcons: Bool {
        account.canView(.version) && viewModel.uiState.platformSections.count > 1
    }

    var body: some View {
        List {
            buildHeaderSection()
            buildRejectedReviewTip()
            buildPlatformSections()
            buildGeneralSection()
            buildAppStoreSection()
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
        .sheet(isPresented: $viewModel.uiState.showPreSubmitSheet) {
            if let checklist = viewModel.uiState.preSubmitChecklist {
                PreSubmitChecklistSheet(
                    checklist: checklist,
                    isSubmitting: viewModel.uiState.isPerformingAction,
                    onSubmit: { Task { await viewModel.confirmPreSubmit() } },
                    onCancel: { viewModel.uiState.showPreSubmitSheet = false }
                )
            }
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
        .overlay {
            if viewModel.uiState.isValidatingSubmit {
                buildValidatingOverlay()
            }
        }
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

    private func buildValidatingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "Checking submission…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 16) {
                // Multi-platform apps hide this single icon; each platform section
                // shows its own real icon instead (see `buildPlatformSection`).
                if !showsPerPlatformIcons {
                    buildAppIcon(url: viewModel.uiState.app.iconUrl.flatMap { URL(string: $0) }, size: 64, radius: 14)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.uiState.app.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(viewModel.uiState.app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    buildPlatformIcons()
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Rejected Review Tip

    private var hasRejectedVersion: Bool {
        viewModel.uiState.versions.contains { version in
            version.appStoreState == .rejected || version.appStoreState == .metadataRejected
        }
    }

    @ViewBuilder
    private func buildRejectedReviewTip() -> some View {
        if hasRejectedVersion {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)

                        Text(String(localized: "One or more builds were rejected by App Review. Open the Resolution Center on the web to review the issues and respond."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Link(destination: URL(string: "https://appstoreconnect.apple.com/apps/\(viewModel.uiState.app.id)/appstore/resolutioncenter")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text(String(localized: "Open Resolution Center"))
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            EmptyView()
        }
    }

    private func buildPlatformIcons() -> some View {
        let supported = supportedPlatforms
        return HStack(spacing: 12) {
            ForEach(AppPlatform.allCases) { platform in
                Image(systemName: platform.icon)
                    .font(.caption)
                    .foregroundStyle(supported.contains(platform) ? Color.blue : Color.gray.opacity(0.4))
                    .help(platform.displayName)
            }
        }
        .padding(.top, 2)
    }

    /// Platforms this app actually ships a binary for, derived from
    /// `platformVersions` (falling back to the single `platform` field).
    private var supportedPlatforms: Set<AppPlatform> {
        let app = viewModel.uiState.app
        var platforms = Set<AppPlatform>()

        for entry in app.platformVersions ?? [] {
            if let platform = AppPlatform.from(entry.platform) {
                platforms.insert(platform)
            }
        }

        if platforms.isEmpty, let raw = app.platform, let platform = AppPlatform.from(raw) {
            platforms.insert(platform)
        }

        return platforms
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
            if showsPerPlatformIcons {
                HStack(spacing: 8) {
                    buildAppIcon(url: platformIconURL(for: section.platform), size: 24, radius: 6)
                    Text(section.platform.displayName)
                }
            } else {
                Label(section.platform.displayName, systemImage: section.platform.icon)
            }
        }
    }

    /// Resolves the icon URL for a platform section with a graceful fallback:
    /// the platform's real build icon → the app's single `iconUrl` →
    /// placeholder (handled by `buildAppIcon` when the URL is nil).
    private func platformIconURL(for platform: AppPlatform) -> URL? {
        let raw = viewModel.uiState.platformIcons[platform] ?? viewModel.uiState.app.iconUrl
        return raw.flatMap { URL(string: $0) }
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

                if let phased = viewModel.uiState.phasedByVersionId[version.id],
                   phased.state == .active || phased.state == .paused,
                   let day = phased.currentDayNumber {
                    buildPhasedReleaseLabel(day: day, paused: phased.state == .paused)
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
                    Task { await viewModel.startSubmitForReview(version) }
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
                homeCoordinator.navigateToSubmissions(
                    appId: viewModel.uiState.app.id,
                    appName: viewModel.uiState.app.name,
                    account: account
                )
            } label: {
                buildMenuRow(
                    icon: "paperplane.fill",
                    color: .blue,
                    title: String(localized: "Submissions"),
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
                    appName: viewModel.uiState.app.name,
                    account: account
                )
            } label: {
                buildMenuRow(icon: "star.fill", color: .yellow, title: String(localized: "Ratings and Reviews"))
            }
        } header: {
            Text("App Store")
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

    private func buildPhasedReleaseLabel(day: Int, paused: Bool) -> some View {
        HStack(spacing: 4) {
            if paused {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            Text(String(localized: "Phased release: \(day) of 7 days"))
                .font(.caption)
                .foregroundStyle(.primary)
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
                    viewModel.prepareCreatePlatform()
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
    @Environment(\.dismiss) private var dismiss

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
                        dismiss()
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
