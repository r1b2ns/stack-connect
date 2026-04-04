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
                CreateBetaGroupSheet { name, isInternal in
                    Task { await viewModel.createGroup(name: name, isInternal: isInternal) }
                } onCancel: {
                    viewModel.uiState.showCreateGroup = false
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

            if !viewModel.uiState.recentBuilds.isEmpty {
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
                    if !group.isInternalGroup && viewModel.uiState.account.canDelete(.testFlight) {
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

    private func buildBuildsSection() -> some View {
        Section {
            ForEach(viewModel.uiState.recentBuilds.prefix(10)) { build in
                buildBuildRow(build)
            }
        } header: {
            Label(String(localized: "Recent Builds"), systemImage: "hammer.fill")
        }
    }

    private func buildBuildRow(_ build: BuildModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: buildStateIcon(build.processingState))
                .font(.body)
                .foregroundStyle(buildStateColor(build.processingState))

            VStack(alignment: .leading, spacing: 2) {
                Text(build.version ?? "–")
                    .font(.body)
                    .fontWeight(.medium)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(buildStateLabel(build.processingState))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(buildStateColor(build.processingState))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(buildStateColor(build.processingState).opacity(0.12))
                .clipShape(Capsule())
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

    let onCreate: (String, Bool) -> Void
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
            }
            .navigationTitle(String(localized: "New Beta Group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) {
                        onCreate(name.trimmingCharacters(in: .whitespaces), isInternal)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
