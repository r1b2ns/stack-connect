import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct CertificateDetailViewFactory {
    static func build(account: AccountModel, certificate: CertificateModel) -> some View {
        CertificateDetailEntry(account: account, certificate: certificate)
    }
}

// MARK: - Entry

private struct CertificateDetailEntry: View {
    @StateObject private var coordinator = CertificateDetailCoordinator()
    @StateObject private var viewModel: CertificateDetailViewModel

    init(account: AccountModel, certificate: CertificateModel) {
        _viewModel = StateObject(
            wrappedValue: CertificateDetailViewModel(account: account, certificate: certificate)
        )
    }

    var body: some View {
        CertificateDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - Share Item

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - View

struct CertificateDetailView<ViewModel: CertificateDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var shareItem: ShareItem?
    @State private var showRevokeConfirmation = false

    private var certificate: CertificateModel {
        viewModel.uiState.certificate
    }

    var body: some View {
        List {
            buildHeaderSection()
            buildDetailsSection()

            if !certificate.isExpired {
                buildActionsSection()
            }

            if let error = viewModel.uiState.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(String(localized: "Certificate"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(
            String(localized: "Revoke this certificate?"),
            isPresented: $showRevokeConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Revoke"), role: .destructive) {
                Task {
                    let success = await viewModel.revoke()
                    if success { dismiss() }
                }
            }
        } message: {
            Text(String(localized: "This action cannot be undone."))
        }
    }

    // MARK: - Sections

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(certificate.isExpired ? Color.red : Color.blue)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(certificate.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(certificate.typeDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func buildDetailsSection() -> some View {
        Section {
            buildRow(
                label: String(localized: "Name"),
                value: certificate.name.isEmpty ? "—" : certificate.name
            )
            buildRow(
                label: String(localized: "Type"),
                value: certificate.typeDisplayName
            )
            if let platform = certificate.platform {
                buildRow(label: String(localized: "Platform"), value: platform)
            }
            if let serial = certificate.serialNumber {
                buildRow(label: String(localized: "Serial Number"), value: serial)
            }
            buildRow(
                label: String(localized: "Status"),
                value: certificate.isExpired
                    ? String(localized: "Expired")
                    : (certificate.isActivated
                        ? String(localized: "Active")
                        : String(localized: "Inactive")),
                valueColor: certificate.isExpired ? .red : .primary
            )
            if let expiration = certificate.expirationDate {
                buildRow(
                    label: String(localized: "Expiration"),
                    value: expiration.formatted(date: .abbreviated, time: .shortened)
                )
            }
            buildRow(label: String(localized: "ID"), value: certificate.id)
        } header: {
            Text(String(localized: "Details"))
        }
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
            .disabled(viewModel.uiState.isPreparingDownload || viewModel.uiState.isRevoking)

            Button(role: .destructive) {
                showRevokeConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "Revoke"), systemImage: "xmark.shield")
                    Spacer()
                    if viewModel.uiState.isRevoking {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.uiState.isPreparingDownload || viewModel.uiState.isRevoking)
        }
    }

    // MARK: - Helpers

    private func buildRow(
        label: String,
        value: String,
        valueColor: Color = .primary
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
