import SwiftUI

// MARK: - Factory

@MainActor
struct FirebaseAppListViewFactory {
    static func build(account: AccountModel, project: FirebaseProjectModel) -> some View {
        FirebaseAppListEntry(account: account, project: project)
    }
}

// MARK: - Entry

private struct FirebaseAppListEntry: View {
    let account: AccountModel
    let project: FirebaseProjectModel

    @StateObject private var viewModel: FirebaseAppListViewModel

    init(account: AccountModel, project: FirebaseProjectModel) {
        self.account = account
        self.project = project
        _viewModel = StateObject(wrappedValue: FirebaseAppListViewModel(account: account, project: project))
    }

    var body: some View {
        FirebaseAppListView(viewModel: viewModel)
    }
}

// MARK: - View

struct FirebaseAppListView<ViewModel: FirebaseAppListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.project.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name, ID or bundle")
            )
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $viewModel.uiState.selectedApp) { app in
                FirebaseAppDetailSheet(
                    app: app,
                    configContent: viewModel.uiState.configContent,
                    configFilename: viewModel.uiState.configFilename,
                    onUpdateNickname: { newName in
                        Task { await viewModel.updateNickname(app, newName: newName) }
                    },
                    onFetchConfig: {
                        Task { await viewModel.fetchConfig(app) }
                    },
                    onDelete: {
                        viewModel.uiState.selectedApp = nil
                        viewModel.uiState.confirmDeleteApp = app
                    },
                    onDismiss: {
                        viewModel.uiState.selectedApp = nil
                        viewModel.uiState.configContent = nil
                        viewModel.uiState.configFilename = nil
                    }
                )
            }
            .sheet(isPresented: $viewModel.uiState.showCreateApp) {
                CreateFirebaseAppSheet { platform, identifier, nickname, appStoreId in
                    Task { await viewModel.createApp(platform: platform, identifier: identifier, nickname: nickname, appStoreId: appStoreId) }
                } onCancel: {
                    viewModel.uiState.showCreateApp = false
                }
            }
            .alert(
                String(localized: "Delete App"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmDeleteApp != nil },
                    set: { if !$0 { viewModel.uiState.confirmDeleteApp = nil } }
                )
            ) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let app = viewModel.uiState.confirmDeleteApp {
                        Task { await viewModel.removeApp(app) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                if let app = viewModel.uiState.confirmDeleteApp {
                    Text("Are you sure you want to delete \(app.displayName)? This action cannot be undone.")
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.filteredApps.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "app.dashed")
            } description: {
                Text("No apps found in this project.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            if !viewModel.uiState.iosApps.isEmpty {
                buildSection(title: "iOS", icon: "apple.logo", color: .blue, apps: viewModel.uiState.iosApps)
            }
            if !viewModel.uiState.androidApps.isEmpty {
                buildSection(title: "Android", icon: "smartphone", color: .green, apps: viewModel.uiState.androidApps)
            }
            if !viewModel.uiState.webApps.isEmpty {
                buildSection(title: "Web", icon: "globe", color: .purple, apps: viewModel.uiState.webApps)
            }
        }
    }

    // MARK: - Section

    private func buildSection(title: String, icon: String, color: Color, apps: [FirebaseAppModel]) -> some View {
        Section {
            ForEach(apps) { app in
                Button {
                    viewModel.uiState.configContent = nil
                    viewModel.uiState.configFilename = nil
                    viewModel.uiState.selectedApp = app
                } label: {
                    buildAppRow(app, color: color)
                }
                .foregroundStyle(.primary)
            }
        } header: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(apps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - App Row

    private func buildAppRow(_ app: FirebaseAppModel, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: app.platform.iconName)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if let identifier = app.platformIdentifier {
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(app.appId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.uiState.showCreateApp = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

// MARK: - App Detail Sheet

struct FirebaseAppDetailSheet: View {

    let app: FirebaseAppModel
    let configContent: String?
    let configFilename: String?
    let onUpdateNickname: (String) -> Void
    let onFetchConfig: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var isEditingNickname = false

    var body: some View {
        NavigationStack {
            List {
                buildInfoSection()
                buildNicknameSection()
                buildConfigSection()
                buildDangerSection()
            }
            .navigationTitle(app.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .onAppear {
                nickname = app.displayName
                onFetchConfig()
            }
        }
    }

    // MARK: - Info

    private func buildInfoSection() -> some View {
        Section {
            HStack {
                Label(String(localized: "Platform"), systemImage: app.platform.iconName)
                Spacer()
                Text(app.platform.displayName)
                    .foregroundStyle(.secondary)
            }

            if let identifier = app.platformIdentifier {
                HStack {
                    Label(String(localized: "Identifier"), systemImage: "textformat")
                    Spacer()
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(String(localized: "App ID"), systemImage: "number")
                Spacer()
                Text(app.appId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } header: {
            Text("Information")
        }
    }

    // MARK: - Nickname

    private func buildNicknameSection() -> some View {
        Section {
            if isEditingNickname {
                HStack {
                    TextField(String(localized: "Nickname"), text: $nickname)
                        .autocorrectionDisabled()

                    Button(String(localized: "Save")) {
                        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onUpdateNickname(trimmed)
                        isEditingNickname = false
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    isEditingNickname = true
                } label: {
                    HStack {
                        Label(String(localized: "Nickname"), systemImage: "pencil")
                        Spacer()
                        Text(app.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Display Name")
        }
    }

    // MARK: - Config

    private func buildConfigSection() -> some View {
        Section {
            if let content = configContent, let filename = configFilename {
                ShareLink(
                    item: content,
                    subject: Text(filename),
                    message: Text(filename)
                ) {
                    HStack {
                        Label(filename, systemImage: "doc.text.fill")
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                HStack {
                    Label(String(localized: "Loading config..."), systemImage: "doc.text.fill")
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Configuration File")
        } footer: {
            if app.platform == .ios {
                Text("GoogleService-Info.plist")
            } else if app.platform == .android {
                Text("google-services.json")
            }
        }
    }

    // MARK: - Danger

    private func buildDangerSection() -> some View {
        Section {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "Delete App"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("The app will be removed from this Firebase project. This may take up to 30 days to complete.")
        }
    }
}

// MARK: - Create Firebase App Sheet (Wizard)

struct CreateFirebaseAppSheet: View {

    let onCreate: (FirebaseAppPlatform, String, String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var selectedPlatform: FirebaseAppPlatform = .ios
    @State private var identifier = ""
    @State private var nickname = ""
    @State private var appStoreId = ""

    var body: some View {
        NavigationStack {
            VStack {
                // Step indicator
                HStack(spacing: 8) {
                    buildStepIndicator(number: 1, isActive: step == 1, isComplete: step > 1)
                    Rectangle()
                        .fill(step > 1 ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                    buildStepIndicator(number: 2, isActive: step == 2, isComplete: false)
                }
                .padding(.top, 16)
                .padding(.horizontal, 40)

                if step == 1 {
                    buildPlatformStep()
                } else {
                    buildDetailsStep()
                }
            }
            .navigationTitle(String(localized: "New App"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == 1 {
                        Button(String(localized: "Next")) {
                            withAnimation { step = 2 }
                        }
                    } else {
                        Button(String(localized: "Create")) {
                            onCreate(selectedPlatform, identifier.trimmingCharacters(in: .whitespaces), nickname.trimmingCharacters(in: .whitespaces), appStoreId.trimmingCharacters(in: .whitespaces))
                        }
                        .disabled(!isStep2Valid)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Platform

    private func buildPlatformStep() -> some View {
        List {
            Section {
                buildPlatformOption(.ios, icon: "apple.logo", color: .blue, subtitle: "iPhone, iPad, Apple Watch")
                buildPlatformOption(.android, icon: "smartphone", color: .green, subtitle: "Android phones and tablets")
                buildPlatformOption(.web, icon: "globe", color: .purple, subtitle: "Web application")
            } header: {
                Text("Select Platform")
            } footer: {
                Text("Choose the platform for your new app.")
            }
        }
    }

    private func buildPlatformOption(_ platform: FirebaseAppPlatform, icon: String, color: Color, subtitle: String) -> some View {
        Button {
            selectedPlatform = platform
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedPlatform == platform {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    // MARK: - Step 2: Details

    private func buildDetailsStep() -> some View {
        List {
            Section {
                if selectedPlatform == .ios {
                    TextField(String(localized: "Bundle ID"), text: $identifier)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } else if selectedPlatform == .android {
                    TextField(String(localized: "Package Name"), text: $identifier)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                TextField(String(localized: "Nickname (optional)"), text: $nickname)

                if selectedPlatform == .ios {
                    TextField(String(localized: "App Store ID (optional)"), text: $appStoreId)
                        .keyboardType(.numberPad)
                }
            } header: {
                Text("App Details")
            } footer: {
                if selectedPlatform == .ios {
                    Text("The Bundle ID must match your Xcode project. Example: com.example.myapp")
                } else if selectedPlatform == .android {
                    Text("The Package Name must match your Android app. Example: com.example.myapp")
                } else {
                    Text("Enter an optional display name for your web app.")
                }
            }
        }
    }

    // MARK: - Helpers

    private var isStep2Valid: Bool {
        if selectedPlatform == .web { return true }
        return !identifier.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func buildStepIndicator(number: Int, isActive: Bool, isComplete: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isActive || isComplete ? Color.accentColor : Color(.systemGray4))
                .frame(width: 28, height: 28)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isActive ? .white : .secondary)
            }
        }
    }
}
