import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayAppListViewFactory {
    static func build(account: AccountModel) -> some View {
        GooglePlayAppListEntry(account: account)
    }
}

// MARK: - Entry

private struct GooglePlayAppListEntry: View {
    let account: AccountModel

    @StateObject private var viewModel: GooglePlayAppListViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: GooglePlayAppListViewModel(account: account))
    }

    var body: some View {
        GooglePlayAppListView(viewModel: viewModel)
    }
}

// MARK: - View

struct GooglePlayAppListView<ViewModel: GooglePlayAppListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $viewModel.uiState.showAddApp) {
                AddGooglePlayAppSheet(
                    isAdding: viewModel.uiState.isAdding,
                    error: viewModel.uiState.addError,
                    onAdd: { packageName in
                        Task { await viewModel.addApp(packageName: packageName) }
                    },
                    onCancel: {
                        viewModel.uiState.showAddApp = false
                        viewModel.uiState.addError = nil
                    }
                )
            }
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing apps...")
            )
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.error, viewModel.uiState.apps.isEmpty {
            StackErrorContentView(
                message: error,
                reportContext: errorReportContext,
                onRetry: { Task { await viewModel.load() } }
            ) {
                if viewModel.uiState.canAddApps {
                    Button(String(localized: "Add Manually")) {
                        viewModel.uiState.showAddApp = true
                    }
                }
            }
        } else if viewModel.uiState.apps.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    /// Where an error on this screen happened, for its shared report (the
    /// account's app list: no app yet).
    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: String(localized: "Apps"), account: viewModel.uiState.account)
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if viewModel.uiState.canAddApps {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "ipod.and.applewatch")
            } description: {
                Text("No apps found for this account. You can add apps manually by package name.")
            } actions: {
                Button(String(localized: "Add App")) {
                    viewModel.uiState.showAddApp = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "ipod.and.applewatch")
            } description: {
                Text("No apps found for this account.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            // Inline banner for a failed sync while the cached list stays on screen.
            if let error = viewModel.uiState.error {
                StackInlineErrorSection(message: error, reportContext: errorReportContext)
            }

            Section {
                ForEach(viewModel.uiState.apps) { app in
                    Button {
                        homeCoordinator.navigateToGooglePlayAppDetail(app, account: viewModel.uiState.account)
                    } label: {
                        buildAppRow(app)
                    }
                    .foregroundStyle(.primary)
                    .contextMenu { buildAppContextMenu(app) }
                }
            }
        }
    }

    private func buildAppRow(_ app: GooglePlayAppItem) -> some View {
        HStack(spacing: 12) {
            // The green Play tile stands in until (or unless) the store icon loads.
            StackAppIcon(url: app.iconURL, size: 40) {
                StackIconTile(systemName: "play.fill", color: .green, size: 40)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(app.packageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if app.isManuallyAdded {
                    Text(String(localized: "Added manually"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func buildAppContextMenu(_ app: GooglePlayAppItem) -> some View {
        if app.isManuallyAdded && viewModel.uiState.canDeleteApps {
            Button(role: .destructive) {
                Task { await viewModel.removeApp(app) }
            } label: {
                Label(String(localized: "Remove"), systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        // Account-level actions (settings, rename, export, delete), as on the
        // App Store app list.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                homeCoordinator.navigateToAccountManagement(viewModel.uiState.account)
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(String(localized: "Manage Account"))
        }

        if viewModel.uiState.canAddApps {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.uiState.showAddApp = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add App"))
            }
        }
    }
}

// MARK: - Add App Sheet

struct AddGooglePlayAppSheet: View {

    let isAdding: Bool
    let error: String?
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    @State private var packageName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(String(localized: "Package Name")) {
                        TextField("com.example.app", text: $packageName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Application")
                } footer: {
                    Text("Enter the Android package name (e.g. com.example.myapp). The service account must have access to this app in the Google Play Console.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Add App"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(String(localized: "Add")) {
                            onAdd(packageName)
                        }
                        .disabled(packageName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
