import SwiftUI

// MARK: - Factory

@MainActor
struct VersionDetailViewFactory {
    static func build(version: AppStoreVersionModel, account: AccountModel) -> some View {
        VersionDetailEntry(version: version, account: account)
    }
}

// MARK: - Entry

private struct VersionDetailEntry: View {
    let version: AppStoreVersionModel
    let account: AccountModel

    @StateObject private var coordinator = VersionDetailCoordinator()
    @StateObject private var viewModel: VersionDetailViewModel

    init(version: AppStoreVersionModel, account: AccountModel) {
        self.version = version
        self.account = account
        _viewModel = StateObject(wrappedValue: VersionDetailViewModel(version: version, account: account))
    }

    var body: some View {
        VersionDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct VersionDetailView<ViewModel: VersionDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    @State private var showBuildBlockedAlert = false
    @State private var showPermissionDenied = false
    @State private var permissionDeniedMessage = ""

    private var account: AccountModel { viewModel.uiState.account }

    private var isMetadataEditable: Bool {
        guard let state = viewModel.uiState.version.appStoreState else { return false }
        return [.prepareForSubmission, .rejected, .developerRejected, .waitingForReview, .readyForReview, .invalidBinary].contains(state)
    }

    /// Metadata editable by state AND user has version.edit permission
    private var canEditMetadata: Bool {
        isMetadataEditable && account.canEdit(.version)
    }

    var body: some View {
        Group {
            if viewModel.uiState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    buildHeaderSection()
                    buildBuildAndMediaSection()
                    buildTextContentSection()
                    buildMetadataSection()
                    buildActionsSection()
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(viewModel.uiState.version.versionString ?? "Version")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $viewModel.uiState.showPromotionalText) {
            StackTextView(
                title: String(localized: "Promotional Text"),
                text: $viewModel.uiState.editPromotionalText,
                readOnly: !canEditMetadata,
                onSave: { try await viewModel.updatePromotionalText() }
            )
        }
        .sheet(isPresented: $viewModel.uiState.showDescription) {
            StackTextView(
                title: String(localized: "Description"),
                text: $viewModel.uiState.editDescription,
                readOnly: !canEditMetadata,
                onSave: { try await viewModel.updateDescription() }
            )
        }
        .sheet(isPresented: $viewModel.uiState.showWhatsNew) {
            StackTextView(
                title: String(localized: "What's New"),
                text: $viewModel.uiState.editWhatsNew,
                readOnly: !canEditMetadata,
                onSave: { try await viewModel.updateWhatsNew() }
            )
        }
        .sheet(isPresented: localizationPickerBinding) {
            if let field = viewModel.uiState.localizationPickerField {
                LocalizationPickerSheet(
                    field: field,
                    localizations: viewModel.uiState.localizations
                ) { localization in
                    handleLocalizationPick(localization, for: field)
                } onCancel: {
                    viewModel.uiState.localizationPickerField = nil
                }
            }
        }
        .sheet(isPresented: $viewModel.uiState.showReleaseSheet) {
            VersionReleaseSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.uiState.showBuildPicker) {
            BuildPickerSheet(
                title: String(localized: "Select Build"),
                appId: viewModel.uiState.version.appId,
                account: viewModel.uiState.account,
                platform: viewModel.uiState.version.platform,
                assignedBuildIds: Set([viewModel.uiState.currentBuild?.id].compactMap { $0 }),
                builds: viewModel.uiState.availableBuilds,
                isLoading: viewModel.uiState.isLoadingBuilds,
                isBusy: viewModel.uiState.isAttachingBuild
            ) { build in
                Task { await viewModel.attachBuild(build) }
            } onCancel: {
                viewModel.uiState.showBuildPicker = false
            }
            .task { await viewModel.loadAvailableBuilds() }
        }
        .sheet(isPresented: $viewModel.uiState.showPhasedReleaseSheet) {
            PhasedReleaseSheet(viewModel: viewModel)
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
        .safeAreaInset(edge: .bottom) {
            buildBottomBar()
        }
        .overlay {
            if viewModel.uiState.isValidatingSubmit {
                buildValidatingOverlay()
            }
        }
        .alert(
            String(localized: "Build Selection"),
            isPresented: $showBuildBlockedAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "The current version status does not allow changing the build."))
        }
        .alert(
            String(localized: "Permission Denied"),
            isPresented: $showPermissionDenied
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(permissionDeniedMessage)
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
                    Task { await performConfirmedAction(action) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.uiState.confirmAction = nil
                }
            }
        } message: {
            if let action = viewModel.uiState.confirmAction {
                Text(action.message(version: viewModel.uiState.version.versionString))
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
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let platform = viewModel.uiState.version.platform {
                        Label(platform.displayName, systemImage: platform.icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let state = viewModel.uiState.version.appStoreState {
                        buildStatusBadge(state: state)
                    }
                }

                Text(viewModel.uiState.version.versionString ?? "–")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Build & Media

    private func buildBuildAndMediaSection() -> some View {
        Section {
            // Build row
            Button {
                if canEditMetadata {
                    viewModel.uiState.showBuildPicker = true
                } else {
                    showBuildBlockedAlert = true
                }
            } label: {
                HStack(spacing: 12) {
                    buildIconSquare(icon: "hammer.fill", color: .gray)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build")
                            .font(.body)
                            .foregroundStyle(.primary)

                        if let build = viewModel.uiState.currentBuild {
                            Text(build.version ?? "–")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No build selected")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Preview and Screenshots
            Button {
                handlePreviewTap()
            } label: {
                buildMenuRow(icon: "photo.on.rectangle.angled", color: .blue, title: String(localized: "Preview and Screenshots"))
            }
        }
    }

    private func handlePreviewTap() {
        if viewModel.uiState.localizations.count > 1 {
            viewModel.uiState.localizationPickerField = .previewAndScreenshots
        } else {
            let localizationId = viewModel.uiState.localizations.first?.id
                ?? viewModel.uiState.localization?.id
            homeCoordinator.navigateToScreenshotPreview(
                versionId: viewModel.uiState.version.id,
                account: viewModel.uiState.account,
                localizationId: localizationId,
                platform: viewModel.uiState.version.platform,
                appStoreState: viewModel.uiState.version.appStoreState
            )
        }
    }

    private var localizationPickerBinding: Binding<Bool> {
        Binding(
            get: { viewModel.uiState.localizationPickerField != nil },
            set: { if !$0 { viewModel.uiState.localizationPickerField = nil } }
        )
    }

    private func handleLocalizationPick(_ localization: AppStoreLocalizationModel, for field: VersionDetailLocalizableField) {
        viewModel.uiState.localizationPickerField = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if field == .previewAndScreenshots {
                homeCoordinator.navigateToScreenshotPreview(
                    versionId: viewModel.uiState.version.id,
                    account: viewModel.uiState.account,
                    localizationId: localization.id,
                    platform: viewModel.uiState.version.platform,
                    appStoreState: viewModel.uiState.version.appStoreState
                )
            } else {
                viewModel.selectLocalization(localization, for: field)
            }
        }
    }

    // MARK: - Text Content

    private func buildTextContentSection() -> some View {
        Section {
            Button { viewModel.requestField(.promotionalText) } label: {
                buildMenuRow(icon: "text.badge.star", color: .purple, title: String(localized: "Promotional Text"))
            }

            Button { viewModel.requestField(.description) } label: {
                buildMenuRow(icon: "doc.text.fill", color: .indigo, title: String(localized: "Description"))
            }

            Button { viewModel.requestField(.whatsNew) } label: {
                buildMenuRow(icon: "sparkles", color: .orange, title: String(localized: "What's New"))
            }
        }
    }

    // MARK: - Metadata (grouped fields + save)

    private func buildMetadataSection() -> some View {
        Section {
            HStack {
                TextField(String(localized: "Keywords"), text: $viewModel.uiState.editKeywords)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!canEditMetadata)
                CopyButton(text: viewModel.uiState.editKeywords)
            }

            HStack {
                TextField(String(localized: "Support URL"), text: $viewModel.uiState.editSupportUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(!canEditMetadata)
                CopyButton(text: viewModel.uiState.editSupportUrl)
            }

            HStack {
                TextField(String(localized: "Marketing URL"), text: $viewModel.uiState.editMarketingUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(!canEditMetadata)
                CopyButton(text: viewModel.uiState.editMarketingUrl)
            }

            HStack {
                TextField(String(localized: "Version"), text: $viewModel.uiState.editVersion)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    .disabled(!canEditMetadata)
                CopyButton(text: viewModel.uiState.editVersion)
            }

            HStack {
                TextField(String(localized: "Copyright"), text: $viewModel.uiState.editCopyright)
                    .disabled(!canEditMetadata)
                CopyButton(text: viewModel.uiState.editCopyright)
            }

            if let error = viewModel.uiState.groupedFieldsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if canEditMetadata {
                Button {
                    Task { await viewModel.saveGroupedFields() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.uiState.isSavingGroupedFields {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.medium)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.uiState.isSavingGroupedFields)
                .foregroundStyle(.accent)
            }
        } header: {
            Text("Metadata")
        }
    }

    // MARK: - Actions

    private var canCompletePhasedRelease: Bool {
        guard viewModel.uiState.version.appStoreState == .readyForSale else { return false }
        guard let state = viewModel.uiState.phasedRelease?.state else { return false }
        return state == .active || state == .paused
    }

    private var canPausePhasedRelease: Bool {
        viewModel.uiState.version.appStoreState == .readyForSale
            && viewModel.uiState.phasedRelease?.state == .active
    }

    private func buildActionsSection() -> some View {
        Section {
            Button {
                guard account.canEdit(.version) else {
                    permissionDeniedMessage = String(localized: "You don't have permission to edit App Review Information.")
                    showPermissionDenied = true
                    return
                }
                homeCoordinator.navigateToAppReviewInfo(
                    versionId: viewModel.uiState.version.id,
                    account: viewModel.uiState.account
                )
            } label: {
                buildMenuRow(icon: "checkmark.shield.fill", color: .green, title: String(localized: "App Review Information"))
            }

            Button {
                guard account.canEdit(.version) else {
                    permissionDeniedMessage = String(localized: "You don't have permission to edit App Store Version Release.")
                    showPermissionDenied = true
                    return
                }
                viewModel.uiState.showReleaseSheet = true
            } label: {
                buildMenuRowWithSubtitle(
                    icon: "arrow.up.circle.fill",
                    color: .cyan,
                    title: String(localized: "App Store Version Release"),
                    subtitle: viewModel.uiState.releaseTypeSubtitle
                )
            }

            Button {
                guard account.canEdit(.version) else {
                    permissionDeniedMessage = String(localized: "You don't have permission to edit Phased Release.")
                    showPermissionDenied = true
                    return
                }
                viewModel.uiState.showPhasedReleaseSheet = true
            } label: {
                buildMenuRowWithSubtitle(
                    icon: "chart.bar.doc.horizontal.fill",
                    color: .teal,
                    title: String(localized: "Phased Release"),
                    subtitle: viewModel.uiState.phasedReleaseSubtitle
                )
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private func buildBottomBar() -> some View {
        if viewModel.uiState.isLoading {
            EmptyView()
        } else {
            buildBottomBarContent()
        }
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

    @ViewBuilder
    private func buildBottomBarContent() -> some View {
        let state = viewModel.uiState.version.appStoreState

        switch state {
        case .prepareForSubmission, .developerRejected:
            if account.canEdit(.version) {
                buildActionBar {
                    buildActionButton(
                        title: String(localized: "Submit for Review"),
                        icon: "paperplane.fill",
                        color: .blue
                    ) {
                        Task { await viewModel.startSubmitForReview() }
                    }
                }
            }

        case .pendingDeveloperRelease:
            buildActionBar {
                HStack(spacing: 12) {
                    if account.canDelete(.version) {
                        buildActionButton(
                            title: String(localized: "Reject"),
                            icon: "xmark.circle.fill",
                            color: .red
                        ) {
                            viewModel.uiState.confirmAction = .reject
                        }
                    }

                    if account.canEdit(.version) {
                        buildActionButton(
                            title: String(localized: "Release"),
                            icon: "arrow.up.circle.fill",
                            color: .green
                        ) {
                            viewModel.uiState.confirmAction = .release
                        }
                    }
                }
            }

        case .inReview, .waitingForReview:
            if account.canEdit(.version) {
                buildActionBar {
                    buildActionButton(
                        title: String(localized: "Cancel Review"),
                        icon: "xmark.circle.fill",
                        color: .red
                    ) {
                        viewModel.uiState.confirmAction = .cancelReview
                    }
                }
            }

        case .readyForReview:
            if account.canEdit(.version) {
                buildActionBar {
                    buildActionButton(
                        title: String(localized: "Cancel Submission"),
                        icon: "xmark.circle.fill",
                        color: .red
                    ) {
                        viewModel.uiState.confirmAction = .cancelSubmission
                    }
                }
            }

        case .readyForSale:
            if canCompletePhasedRelease && account.canEdit(.version) {
                buildActionBar {
                    VStack(spacing: 12) {
                        if canPausePhasedRelease {
                            buildOutlinedActionButton(
                                title: String(localized: "Pause"),
                                icon: "pause.circle.fill",
                                color: .orange
                            ) {
                                Task { await viewModel.setPhasedReleasePaused(true) }
                            }
                        }

                        buildActionButton(
                            title: String(localized: "Release to All Users"),
                            icon: "person.3.fill",
                            color: .green
                        ) {
                            viewModel.uiState.confirmAction = .completePhasedRelease
                        }
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    private func buildActionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .background(.bar)
        .disabled(viewModel.uiState.isPerformingAction)
        .overlay {
            if viewModel.uiState.isPerformingAction {
                ProgressView()
            }
        }
    }

    private func buildActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func buildOutlinedActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(color)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func performConfirmedAction(_ action: VersionDetailAction) async {
        switch action {
        case .submitForReview:       await viewModel.submitForReview()
        case .cancelReview:          await viewModel.cancelReview()
        case .cancelSubmission:      await viewModel.cancelSubmission()
        case .release:               await viewModel.releaseVersion()
        case .reject:                await viewModel.rejectVersion()
        case .completePhasedRelease: await viewModel.completePhasedRelease()
        }
    }

    // MARK: - Reusable Components

    private func buildMenuRowWithSubtitle(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            buildIconSquare(icon: icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildMenuRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 12) {
            buildIconSquare(icon: icon, color: color)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildIconSquare(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func buildStatusBadge(state: AppStoreState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(state.color))
                .frame(width: 8, height: 8)
            Text(state.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
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
}

// MARK: - Version Release Sheet

struct VersionReleaseSheet<ViewModel: VersionDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(VersionReleaseType.allCases) { type in
                        Button {
                            viewModel.uiState.selectedReleaseType = type
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                Text(type.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if viewModel.uiState.selectedReleaseType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if viewModel.uiState.selectedReleaseType == .scheduled {
                    Section {
                        DatePicker(
                            String(localized: "Release Date"),
                            selection: $viewModel.uiState.scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let error = viewModel.uiState.releaseError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "App Store Version Release"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        viewModel.uiState.showReleaseSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.uiState.isSavingRelease {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save")) {
                            Task { await viewModel.saveReleaseType() }
                        }
                    }
                }
            }
            .disabled(viewModel.uiState.isSavingRelease)
        }
    }
}

// MARK: - Phased Release Sheet

struct PhasedReleaseSheet<ViewModel: VersionDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var isPhasedActive: Bool {
        viewModel.uiState.phasedRelease != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await viewModel.savePhasedRelease(usePhased: false) }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.forward.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            Text("Release update to all users immediately")
                                .font(.body)
                                .foregroundStyle(isPhasedActive ? .secondary : .primary)

                            Spacer()

                            if !isPhasedActive {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isPhasedActive)
                    .foregroundStyle(.primary)

                    Button {
                        Task { await viewModel.savePhasedRelease(usePhased: true) }
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.doc.horizontal.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            Text("Release update over 7-day period using phased release")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            if viewModel.uiState.phasedRelease != nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                if isPhasedActive, let phased = viewModel.uiState.phasedRelease {
                    Section {
                        if let state = phased.state {
                            HStack {
                                Text("Status")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(state.displayName)
                            }
                            .font(.subheadline)
                        }

                        if let day = phased.currentDayNumber {
                            HStack {
                                Text("Current Day")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(day) of 7")
                            }
                            .font(.subheadline)

                            let percentage = phasedReleasePercentage(forDay: day)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Users receiving update")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(percentage)%")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                ProgressView(value: Double(percentage), total: 100)
                                    .tint(.teal)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Phased Release Status")
                    }

                    if phased.state == .active || phased.state == .paused {
                        Section {
                            Button {
                                Task { await viewModel.setPhasedReleasePaused(phased.state != .paused) }
                            } label: {
                                HStack {
                                    Image(systemName: phased.state == .paused ? "play.circle.fill" : "pause.circle.fill")
                                        .foregroundStyle(phased.state == .paused ? .green : .orange)
                                        .frame(width: 24)

                                    Text(phased.state == .paused
                                         ? String(localized: "Resume Phased Release")
                                         : String(localized: "Pause Phased Release"))
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                            }
                        }
                    }
                }

                if let error = viewModel.uiState.phasedReleaseError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Phased Release"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        viewModel.uiState.showPhasedReleaseSheet = false
                    }
                }
            }
            .disabled(viewModel.uiState.isSavingPhasedRelease)
            .overlay {
                if viewModel.uiState.isSavingPhasedRelease {
                    ProgressView()
                }
            }
        }
    }

    private func phasedReleasePercentage(forDay day: Int) -> Int {
        switch day {
        case 1: return 1
        case 2: return 2
        case 3: return 5
        case 4: return 10
        case 5: return 20
        case 6: return 50
        default: return 100
        }
    }
}

// MARK: - Localization Picker Sheet

struct LocalizationPickerSheet: View {

    let field: VersionDetailLocalizableField
    let localizations: [AppStoreLocalizationModel]
    let onSelect: (AppStoreLocalizationModel) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(localizations) { localization in
                    Button {
                        onSelect(localization)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localeName(localization.locale))
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                if let code = localization.locale {
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
            }
        }
    }

    private func localeName(_ code: String?) -> String {
        guard let code else { return "–" }
        return Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
