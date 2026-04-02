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
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.error, viewModel.uiState.apps.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "Retry")) {
                    Task { await viewModel.load() }
                }

                Button(String(localized: "Add Manually")) {
                    viewModel.uiState.showAddApp = true
                }
            }
        } else if viewModel.uiState.apps.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "apps.iphone")
            } description: {
                Text("No apps found for this account. You can add apps manually by package name.")
            } actions: {
                Button(String(localized: "Add App")) {
                    viewModel.uiState.showAddApp = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.apps) { app in
                buildAppRow(app)
            }
        }
    }

    private func buildAppRow(_ app: GooglePlayAppItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 9))

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
        .contextMenu {
            if app.isManuallyAdded {
                Button(role: .destructive) {
                    Task { await viewModel.removeApp(app) }
                } label: {
                    Label(String(localized: "Remove"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.uiState.showAddApp = true
            } label: {
                Image(systemName: "plus")
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
