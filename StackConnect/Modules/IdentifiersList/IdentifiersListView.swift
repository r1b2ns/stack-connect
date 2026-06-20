import SwiftUI

// MARK: - Factory

@MainActor
struct IdentifiersListViewFactory {
    static func build(account: AccountModel) -> some View {
        IdentifiersListEntry(account: account)
    }
}

// MARK: - Entry

private struct IdentifiersListEntry: View {
    @StateObject private var coordinator = IdentifiersListCoordinator()
    @StateObject private var viewModel: IdentifiersListViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: IdentifiersListViewModel(account: account))
    }

    var body: some View {
        IdentifiersListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct IdentifiersListView<ViewModel: IdentifiersListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @State private var showCreate = false

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Identifiers"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search identifiers")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "New Identifier"))
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                CreateBundleIdSheet(viewModel: viewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bundleIdDeleted)) { notification in
                if let id = notification.object as? String {
                    viewModel.remove(id: id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bundleIdUpdated)) { notification in
                if let model = notification.object as? BundleIdentifierModel {
                    viewModel.upsert(model)
                }
            }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.bundleIds.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.pendingAgreement {
            PendingAgreementTip()
        } else if viewModel.uiState.filtered.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Identifiers"), systemImage: "ipod.and.applewatch")
            } description: {
                if let error = viewModel.uiState.errorMessage {
                    Text(error)
                } else {
                    Text(String(localized: "No bundle identifiers found for this account."))
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.filtered) { bundle in
                Button {
                    homeCoordinator.navigateToIdentifierDetail(
                        bundleId: bundle,
                        account: viewModel.uiState.account
                    )
                } label: {
                    buildRow(bundle)
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private func buildRow(_ bundle: BundleIdentifierModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "ipod.and.applewatch")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(bundle.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(bundle.identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Create sheet

private struct CreateBundleIdSheet<ViewModel: IdentifiersListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var identifier = ""
    @State private var name = ""
    @State private var platformRaw = "IOS"

    private let platforms = [
        (raw: "IOS",       label: String(localized: "iOS, tvOS, watchOS, visionOS")),
        (raw: "MAC_OS",    label: String(localized: "macOS")),
        (raw: "UNIVERSAL", label: String(localized: "Universal"))
    ]

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !viewModel.uiState.isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Bundle ID"), text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "Identifier"))
                } footer: {
                    Text(String(localized: "Reverse-DNS format, e.g. com.company.app"))
                        .font(.caption)
                }

                Section {
                    TextField(String(localized: "Description"), text: $name)
                } header: {
                    Text(String(localized: "Name"))
                }

                Section {
                    Picker(String(localized: "Platform"), selection: $platformRaw) {
                        ForEach(platforms, id: \.raw) { platform in
                            Text(platform.label).tag(platform.raw)
                        }
                    }
                } header: {
                    Text(String(localized: "Platform"))
                }

                if let error = viewModel.uiState.createErrorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "New Identifier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.uiState.isCreating {
                        ProgressView()
                    } else {
                        Button(String(localized: "Create")) {
                            Task {
                                let ok = await viewModel.create(
                                    identifier: identifier.trimmingCharacters(in: .whitespaces),
                                    name: name.trimmingCharacters(in: .whitespaces),
                                    platformRaw: platformRaw
                                )
                                if ok { dismiss() }
                            }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
    }
}
