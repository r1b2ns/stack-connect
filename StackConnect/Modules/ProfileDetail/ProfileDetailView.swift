import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct ProfileDetailViewFactory {
    static func build(account: AccountModel, profile: ProvisioningProfileModel) -> some View {
        ProfileDetailEntry(account: account, profile: profile)
    }
}

// MARK: - Entry

private struct ProfileDetailEntry: View {
    @StateObject private var coordinator = ProfileDetailCoordinator()
    @StateObject private var viewModel: ProfileDetailViewModel

    init(account: AccountModel, profile: ProvisioningProfileModel) {
        _viewModel = StateObject(
            wrappedValue: ProfileDetailViewModel(account: account, profile: profile)
        )
    }

    var body: some View {
        ProfileDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - Share item

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - View

struct ProfileDetailView<ViewModel: ProfileDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var shareItem: ShareItem?
    @State private var showDeleteConfirmation = false

    private var profile: ProvisioningProfileModel {
        viewModel.uiState.profile
    }

    var body: some View {
        List {
            buildHeaderSection()
            buildDetailsSection()
            if profile.isActive && !profile.isExpired {
                buildActionsSection()
            } else {
                buildDeleteOnlySection()
            }
        }
        .navigationTitle(String(localized: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(
            String(localized: "Delete this profile?"),
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
            isPresented: Binding(
                get: { viewModel.uiState.errorMessage != nil },
                set: { newValue in
                    if !newValue { viewModel.uiState.errorMessage = nil }
                }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel.uiState.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.largeTitle)
                    .foregroundStyle(profile.isExpired || !profile.isActive ? Color.red : Color.blue)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(profile.typeDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func buildDetailsSection() -> some View {
        Section {
            buildRow(label: String(localized: "Type"), value: profile.typeDisplayName)
            if let platform = profile.platform {
                buildRow(label: String(localized: "Platform"), value: platform)
            }
            if let bundleId = profile.bundleId {
                buildRow(label: String(localized: "Bundle ID"), value: bundleId)
            }
            if let uuid = profile.uuid {
                buildRow(label: String(localized: "UUID"), value: uuid, monospaced: true)
            }
            buildRow(
                label: String(localized: "Status"),
                value: statusText,
                valueColor: profile.isExpired || !profile.isActive ? .red : .primary
            )
            if let createdDate = profile.createdDate {
                buildRow(
                    label: String(localized: "Created"),
                    value: createdDate.formatted(date: .abbreviated, time: .shortened)
                )
            }
            if let expiration = profile.expirationDate {
                buildRow(
                    label: String(localized: "Expiration"),
                    value: expiration.formatted(date: .abbreviated, time: .shortened),
                    valueColor: profile.isExpired ? .red : .primary
                )
            }
            buildRow(label: String(localized: "ID"), value: profile.id)
        } header: {
            Text(String(localized: "Details"))
        }
    }

    private var statusText: String {
        if profile.isExpired { return String(localized: "Expired") }
        if !profile.isActive { return String(localized: "Invalid") }
        return String(localized: "Active")
    }

    private func buildActionsSection() -> some View {
        Section {
            Button {
                Task {
                    if let url = await viewModel.prepareDownload() {
                        shareItem = ShareItem(url: url)
                    }
                }
            } label: {
                HStack {
                    Label(String(localized: "Download"), systemImage: "square.and.arrow.down")
                    Spacer()
                    if viewModel.uiState.isPreparingDownload {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.uiState.isPreparingDownload || viewModel.uiState.isDeleting)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "Delete"), systemImage: "trash")
                    Spacer()
                    if viewModel.uiState.isDeleting {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.uiState.isPreparingDownload || viewModel.uiState.isDeleting)
        }
    }

    /// For expired/invalid profiles, only the Delete action is offered (download yields nothing useful).
    private func buildDeleteOnlySection() -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "Delete"), systemImage: "trash")
                    Spacer()
                    if viewModel.uiState.isDeleting {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.uiState.isDeleting)
        } footer: {
            Text(String(localized: "Expired or invalid profiles can only be deleted."))
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func buildRow(
        label: String,
        value: String,
        valueColor: Color = .primary,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .modifier(MonospacedIfNeeded(monospaced: monospaced))
        }
        .font(.subheadline)
    }
}

private struct MonospacedIfNeeded: ViewModifier {
    let monospaced: Bool
    func body(content: Content) -> some View {
        if monospaced {
            content.font(.system(.subheadline, design: .monospaced))
        } else {
            content
        }
    }
}

// MARK: - Share sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
