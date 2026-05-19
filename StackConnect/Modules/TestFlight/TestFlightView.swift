import SwiftUI

// MARK: - Factory

@MainActor
struct TestFlightViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        TestFlightEntryView(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct TestFlightEntryView: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: TestFlightViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: TestFlightViewModel(appId: appId, account: account))
    }

    var body: some View {
        TestFlightView(viewModel: viewModel)
    }
}

// MARK: - View

struct TestFlightView<ViewModel: TestFlightViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "TestFlight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $viewModel.uiState.showCreateGroup) {
                CreateBetaGroupSheet(
                    isCreating: viewModel.uiState.isCreatingGroup
                ) { name, isInternal, hasAccessToAllBuilds in
                    Task {
                        await viewModel.createGroup(
                            name: name,
                            isInternal: isInternal,
                            hasAccessToAllBuilds: hasAccessToAllBuilds
                        )
                    }
                } onCancel: {
                    viewModel.uiState.showCreateGroup = false
                }
            }
            .alert(
                String(localized: "Expire Build"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmExpireBuild != nil },
                    set: { if !$0 { viewModel.uiState.confirmExpireBuild = nil } }
                )
            ) {
                Button(String(localized: "Expire"), role: .destructive) {
                    if let build = viewModel.uiState.confirmExpireBuild {
                        Task { await viewModel.expireBuild(build) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                if let build = viewModel.uiState.confirmExpireBuild {
                    Text("Expire build \(build.displayVersion)? Testers will no longer be able to install it. This cannot be undone via the API.")
                }
            }
            .alert(
                String(localized: "Expire Failed"),
                isPresented: Binding(
                    get: { viewModel.uiState.expireError != nil },
                    set: { if !$0 { viewModel.uiState.expireError = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                if let message = viewModel.uiState.expireError {
                    Text(message)
                }
            }
            .alert(
                String(localized: "Delete Group"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmDelete != nil },
                    set: { if !$0 { viewModel.uiState.confirmDelete = nil } }
                )
            ) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let group = viewModel.uiState.confirmDelete {
                        Task { await viewModel.deleteGroup(group) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                if let group = viewModel.uiState.confirmDelete {
                    Text("Are you sure you want to delete the group \"\(group.name)\"?")
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
            .overlay {
                if viewModel.uiState.isExpiringBuild {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    .ignoresSafeArea()
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.groups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.groups.isEmpty && viewModel.uiState.builds.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Beta Groups"), systemImage: "airplane")
            } description: {
                Text("Create a beta group to start testing with TestFlight.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            if !viewModel.uiState.internalGroups.isEmpty {
                buildGroupSection(
                    title: String(localized: "Internal Testing"),
                    icon: "lock.fill",
                    groups: viewModel.uiState.internalGroups
                )
            }

            if !viewModel.uiState.externalGroups.isEmpty {
                buildGroupSection(
                    title: String(localized: "External Testing"),
                    icon: "globe",
                    groups: viewModel.uiState.externalGroups
                )
            }

            if !viewModel.uiState.buildsByPlatform.isEmpty {
                buildBuildsSection()
            }
        }
    }

    // MARK: - Group Section

    private func buildGroupSection(title: String, icon: String, groups: [BetaGroupModel]) -> some View {
        Section {
            ForEach(groups) { group in
                Button {
                    homeCoordinator.navigateToBetaGroupDetail(group: group, appId: viewModel.uiState.appId, account: viewModel.uiState.account)
                } label: {
                    buildGroupRow(group)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if viewModel.uiState.account.canDelete(.testFlight) {
                        Button(role: .destructive) {
                            viewModel.uiState.confirmDelete = group
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Label(title, systemImage: icon)
        }
    }

    private func buildGroupRow(_ group: BetaGroupModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.isInternalGroup ? "lock.shield.fill" : "globe")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(group.isInternalGroup ? Color.blue : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Label("\(group.testerCount ?? 0)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if group.isPublicLinkEnabled {
                        Label(String(localized: "Public Link"), systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Builds Section

    @ViewBuilder
    private func buildBuildsSection() -> some View {
        ForEach(viewModel.uiState.buildsByPlatform, id: \.platform) { group in
            buildPlatformSection(group)
        }
    }

    private func buildPlatformSection(_ group: PlatformBuildGroup) -> some View {
        Section {
            ForEach(group.builds.prefix(5)) { build in
                Button {
                    homeCoordinator.navigateToBuildDetail(
                        build: build,
                        appId: viewModel.uiState.appId,
                        account: viewModel.uiState.account
                    )
                } label: {
                    buildBuildRow(build)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) {
                    if !build.isExpired && viewModel.uiState.account.canDelete(.testFlight) {
                        Button {
                            viewModel.uiState.confirmExpireBuild = build
                        } label: {
                            Label(String(localized: "Expire"), systemImage: "clock.badge.xmark")
                        }
                        .tint(.orange)
                    }
                }
            }

            if group.builds.count > 5 {
                Button {
                    homeCoordinator.navigateToPlatformBuildsList(
                        appId: viewModel.uiState.appId,
                        platform: group.platform,
                        account: viewModel.uiState.account
                    )
                } label: {
                    HStack {
                        Text(String(localized: "See More"))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.tint)
            }
        } header: {
            Label(BuildPlatform.label(for: group.platform), systemImage: BuildPlatform.icon(for: group.platform))
        }
    }

    private func buildBuildRow(_ build: BuildModel) -> some View {
        let icon = build.isExpired ? "clock.badge.xmark" : buildStateIcon(build.processingState)
        let label = build.isExpired ? String(localized: "Expired") : buildStateLabel(build.processingState)
        let color: Color = build.isExpired ? .gray : buildStateColor(build.processingState)

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)
                    .truncationMode(.middle)
                    .lineLimit(1)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12))
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if viewModel.uiState.account.canAdd(.testFlight) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.uiState.showCreateGroup = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func buildStateIcon(_ state: String?) -> String {
        switch state {
        case "VALID":      return "checkmark.circle.fill"
        case "PROCESSING": return "arrow.triangle.2.circlepath"
        case "FAILED":     return "xmark.circle.fill"
        case "INVALID":    return "exclamationmark.circle.fill"
        default:           return "circle"
        }
    }

    private func buildStateColor(_ state: String?) -> Color {
        switch state {
        case "VALID":      return .green
        case "PROCESSING": return .orange
        case "FAILED":     return .red
        case "INVALID":    return .red
        default:           return .gray
        }
    }

    private func buildStateLabel(_ state: String?) -> String {
        switch state {
        case "VALID":      return String(localized: "Ready")
        case "PROCESSING": return String(localized: "Processing")
        case "FAILED":     return String(localized: "Failed")
        case "INVALID":    return String(localized: "Invalid")
        default:           return "–"
        }
    }
}

// MARK: - Create Beta Group Sheet

struct CreateBetaGroupSheet: View {

    @State private var name = ""
    @State private var isInternal = false
    @State private var hasAccessToAllBuilds = false

    let isCreating: Bool
    let onCreate: (String, Bool, Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Group Name"), text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                }

                Section {
                    Toggle(String(localized: "Internal Group"), isOn: $isInternal)
                } footer: {
                    Text(isInternal
                         ? "Internal testers are members of your App Store Connect team. Up to 100 testers."
                         : "External testers are invited via email or public link. Up to 10,000 testers. Requires Beta App Review."
                    )
                }

                if isInternal {
                    Section {
                        Toggle(String(localized: "Enable automatic distribution"), isOn: $hasAccessToAllBuilds)
                    } footer: {
                        Text("Automatically distribute new builds for this app to testers in this group. This setting can only be changed in App Store Connect (web) after the group is created.")
                    }
                }
            }
            .navigationTitle(String(localized: "New Beta Group"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isCreating)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button(String(localized: "Create")) {
                            onCreate(
                                name.trimmingCharacters(in: .whitespaces),
                                isInternal,
                                isInternal ? hasAccessToAllBuilds : false
                            )
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
