import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Factory

@MainActor
struct CreateCertificateViewFactory {
    static func build(account: AccountModel) -> some View {
        CreateCertificateEntry(account: account)
    }
}

// MARK: - Entry

private struct CreateCertificateEntry: View {
    @StateObject private var coordinator = CreateCertificateCoordinator()
    @StateObject private var viewModel: CreateCertificateViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: CreateCertificateViewModel(account: account))
    }

    var body: some View {
        CreateCertificateView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - Share Item

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - View

struct CreateCertificateView<ViewModel: CreateCertificateViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var shareItem: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            buildStepIndicator()
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

            buildStepContent()
        }
        .navigationTitle(String(localized: "New Certificate"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.uiState.step == .generated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data, .text, .plainText, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel.loadCSR(from: url) }
                }
            case .failure(let error):
                Log.print.error("[CreateCertificate] File import failed: \(error.localizedDescription)")
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Step indicator

    private func buildStepIndicator() -> some View {
        HStack(spacing: 8) {
            buildStepDot(.selectType, label: "1")
            buildStepConnector(active: viewModel.uiState.step.rawValue >= 1)
            buildStepDot(.uploadCSR, label: "2")
            buildStepConnector(active: viewModel.uiState.step.rawValue >= 2)
            buildStepDot(.generated, label: "3")
        }
    }

    private func buildStepDot(_ step: CreateCertificateStep, label: String) -> some View {
        let current = viewModel.uiState.step
        let active = step.rawValue <= current.rawValue
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(active ? Color.blue : Color.gray.opacity(0.25))
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text(step.displayName)
                .font(.caption2)
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    private func buildStepConnector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Color.blue : Color.gray.opacity(0.25))
            .frame(height: 2)
            .padding(.bottom, 18)
    }

    // MARK: - Step content

    @ViewBuilder
    private func buildStepContent() -> some View {
        switch viewModel.uiState.step {
        case .selectType:
            buildTypeStep()
        case .uploadCSR:
            buildUploadStep()
        case .generated:
            buildGeneratedStep()
        }
    }

    // MARK: - Step 1: Type

    private func buildTypeStep() -> some View {
        List {
            ForEach(CertificateTypeSection.allCases) { section in
                Section {
                    ForEach(CertificateTypeOption.allCases.filter { $0.section == section }) { option in
                        buildTypeRow(option)
                    }
                } header: {
                    Text(section.displayName)
                } footer: {
                    if section == .services {
                        Text(String(localized: "Some service certificates can only be created on developer.apple.com."))
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func buildTypeRow(_ option: CertificateTypeOption) -> some View {
        Button {
            viewModel.selectType(option)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .foregroundStyle(option.isSupportedByAPI ? .primary : .secondary)

                    if !option.isSupportedByAPI {
                        Text(String(localized: "Available only on developer.apple.com"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if option.relationshipKind == .passTypeId {
                        Text(String(localized: "Requires a Pass Type ID"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if option.relationshipKind == .merchantId {
                        Text(String(localized: "Requires a Merchant ID and accepted agreement"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if option.isSupportedByAPI {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!option.isSupportedByAPI)
    }

    // MARK: - Step 2: Upload CSR

    private func buildUploadStep() -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                        Text(viewModel.uiState.selectedType?.displayName ?? "")
                            .font(.subheadline)
                    }
                } header: {
                    Text(String(localized: "Selected Type"))
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.uiState.csrFileName ?? String(localized: "Choose CSR file"))
                                    .foregroundStyle(.primary)
                                Text(viewModel.uiState.csrFileName == nil
                                     ? String(localized: "Pick a .certSigningRequest from Files")
                                     : String(localized: "Tap to choose another file"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                } header: {
                    Text(String(localized: "Certificate Signing Request"))
                } footer: {
                    Text(String(localized: "Generate a CSR with Keychain Access on Mac (Certificate Assistant → Request a Certificate from a Certificate Authority)."))
                        .font(.caption)
                }

                if let kind = viewModel.uiState.selectedType?.relationshipKind {
                    Section {
                        TextField(
                            kind == .passTypeId ? String(localized: "Pass Type ID") : String(localized: "Merchant ID"),
                            text: $viewModel.uiState.relationshipId
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } header: {
                        Text(kind == .passTypeId ? String(localized: "Pass Type ID") : String(localized: "Merchant ID"))
                    } footer: {
                        Text(kind == .passTypeId
                             ? String(localized: "Resource ID of an existing Pass Type ID. Required by the API.")
                             : String(localized: "Resource ID of an existing Merchant ID. Requires the Apple Pay Platform Web Merchant Terms to be accepted."))
                            .font(.caption)
                    }
                }

                if let error = viewModel.uiState.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        if viewModel.uiState.isCreating {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(String(localized: "Create Certificate"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmit || viewModel.uiState.isCreating)

                Button(String(localized: "Back")) {
                    viewModel.goBack()
                }
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var canSubmit: Bool {
        guard viewModel.uiState.csrContent?.isEmpty == false else { return false }
        return true
    }

    // MARK: - Step 3: Generated

    @ViewBuilder
    private func buildGeneratedStep() -> some View {
        if let cert = viewModel.uiState.createdCertificate {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Certificate Created"))
                                .font(.headline)
                            Text(cert.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    buildDetailRow(label: String(localized: "Type"), value: cert.typeDisplayName)
                    if let platform = cert.platform {
                        buildDetailRow(label: String(localized: "Platform"), value: platform)
                    }
                    if let serial = cert.serialNumber {
                        buildDetailRow(label: String(localized: "Serial Number"), value: serial)
                    }
                    if let expiration = cert.expirationDate {
                        buildDetailRow(
                            label: String(localized: "Expiration"),
                            value: expiration.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    buildDetailRow(label: String(localized: "ID"), value: cert.id)
                } header: {
                    Text(String(localized: "Details"))
                }

                Section {
                    Button {
                        if let url = viewModel.prepareDownload() {
                            shareItem = ShareItem(url: url)
                        }
                    } label: {
                        Label(String(localized: "Download"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.uiState.createdContentBase64 == nil)
                }

                if let error = viewModel.uiState.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func buildDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
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
