import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct IdentifierDetailViewFactory {
    static func build(account: AccountModel, bundleId: BundleIdentifierModel) -> some View {
        IdentifierDetailEntry(account: account, bundleId: bundleId)
    }
}

// MARK: - Entry

private struct IdentifierDetailEntry: View {
    @StateObject private var coordinator = IdentifierDetailCoordinator()
    @StateObject private var viewModel: IdentifierDetailViewModel

    init(account: AccountModel, bundleId: BundleIdentifierModel) {
        _viewModel = StateObject(wrappedValue: IdentifierDetailViewModel(account: account, bundleId: bundleId))
    }

    var body: some View {
        IdentifierDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct IdentifierDetailView<ViewModel: IdentifierDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedName = ""
    @State private var showDeleteConfirmation = false
    @State private var showAddCapability = false

    private var bundle: BundleIdentifierModel {
        viewModel.uiState.bundleId
    }

    private var nameChanged: Bool {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines) != bundle.name &&
        !editedName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Show errors from rename / delete / disableCapability actions as a prominent alert.
    /// While the AddCapability sheet is open, its own inline section handles errors.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.uiState.errorMessage != nil && !showAddCapability },
            set: { newValue in
                if !newValue { viewModel.uiState.errorMessage = nil }
            }
        )
    }

    var body: some View {
        List {
            buildNameSection()
            buildDetailsSection()
            buildCapabilitiesSection()
            buildDangerZoneSection()
        }
        .navigationTitle(bundle.identifier)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            editedName = bundle.name
            await viewModel.load()
        }
        .alert(
            String(localized: "Delete this identifier?"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    let ok = await viewModel.delete()
                    if ok { dismiss() }
                }
            }
        } message: {
            Text(String(localized: "This action cannot be undone."))
        }
        .alert(
            String(localized: "Apple rejected this change"),
            isPresented: errorAlertBinding
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel.uiState.errorMessage ?? "")
        }
        .sheet(isPresented: $showAddCapability) {
            AddCapabilitySheet(viewModel: viewModel)
        }
    }

    // MARK: - Sections

    private func buildNameSection() -> some View {
        Section {
            TextField(String(localized: "Name"), text: $editedName)

            if nameChanged {
                Button {
                    Task {
                        let ok = await viewModel.rename(to: editedName)
                        if ok {
                            editedName = viewModel.uiState.bundleId.name
                        }
                    }
                } label: {
                    HStack {
                        Text(String(localized: "Save Name"))
                        Spacer()
                        if viewModel.uiState.isRenaming {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.uiState.isRenaming)
            }
        } header: {
            Text(String(localized: "Name"))
        }
    }

    private func buildDetailsSection() -> some View {
        Section {
            buildCopyableRow(label: String(localized: "Bundle ID"), value: bundle.identifier)
            buildCopyableRow(label: String(localized: "Platform"), value: bundle.platformDisplayName, copyValue: bundle.platform)
            if let seedId = bundle.seedId {
                buildCopyableRow(label: String(localized: "Seed ID"), value: seedId)
            }
            buildCopyableRow(label: String(localized: "ID"), value: bundle.id)
        } header: {
            Text(String(localized: "Details"))
        }
    }

    private func buildCapabilitiesSection() -> some View {
        Section {
            if viewModel.uiState.isLoadingCapabilities && viewModel.uiState.capabilities.isEmpty {
                HStack {
                    ProgressView()
                    Text(String(localized: "Loading capabilities…"))
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.uiState.capabilities.isEmpty {
                Text(String(localized: "No capabilities enabled."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.uiState.capabilities.sorted(by: { $0.displayName < $1.displayName })) { cap in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(cap.displayName)
                        Spacer()
                        if viewModel.uiState.pendingCapabilityType == cap.capabilityType {
                            ProgressView()
                        } else {
                            Button(role: .destructive) {
                                Task { await viewModel.disableCapability(id: cap.id) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Button {
                showAddCapability = true
            } label: {
                Label(String(localized: "Add Capability"), systemImage: "plus.circle")
            }
        } header: {
            Text(String(localized: "Capabilities"))
        } footer: {
            Text(String(localized: "Some capabilities require additional configuration on developer.apple.com (containers, App Groups, etc.)."))
                .font(.caption)
        }
    }

    private func buildDangerZoneSection() -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "Delete Identifier"), systemImage: "trash")
                    Spacer()
                    if viewModel.uiState.isDeleting {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.uiState.isDeleting)
        }
    }

    private func buildRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    /// Same row as `buildRow` but with a copy button on the right.
    /// `copyValue` lets the copied text differ from the display text (e.g. copy the raw platform code instead of the localized label).
    private func buildCopyableRow(label: String, value: String, copyValue: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = copyValue ?? value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Copy \(label)"))
        }
        .font(.subheadline)
    }
}

// MARK: - Add capability sheet

private struct AddCapabilitySheet<ViewModel: IdentifierDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var availableEntries: [CapabilityCatalogEntry] {
        let enabledTypes = Set(viewModel.uiState.capabilities.map { $0.capabilityType })
        let pool = CapabilityCatalog.all.filter { !enabledTypes.contains($0.raw) }
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return pool }
        return pool.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableEntries) { entry in
                    Button {
                        Task { await viewModel.enableCapability(typeRaw: entry.raw) }
                    } label: {
                        HStack {
                            Text(entry.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.uiState.pendingCapabilityType == entry.raw {
                                ProgressView()
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .disabled(viewModel.uiState.pendingCapabilityType != nil)
                }

                if availableEntries.isEmpty {
                    Text(String(localized: "All available capabilities are already enabled."))
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.uiState.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "Add Capability"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: String(localized: "Search capabilities"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }
}
