import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct CreateProfileViewFactory {
    static func build(account: AccountModel) -> some View {
        CreateProfileEntry(account: account)
    }
}

// MARK: - Entry

private struct CreateProfileEntry: View {
    @StateObject private var coordinator = CreateProfileCoordinator()
    @StateObject private var viewModel: CreateProfileViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: CreateProfileViewModel(account: account))
    }

    var body: some View {
        CreateProfileView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - Share item

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - View

struct CreateProfileView<ViewModel: CreateProfileViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var shareItem: ShareItem?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            buildStepIndicator()
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

            buildStepContent()
        }
        .navigationTitle(String(localized: "New Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.uiState.step == .generated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .task { await viewModel.loadResources() }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(
            String(localized: "Apple rejected this request"),
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

    // MARK: - Step indicator

    private func buildStepIndicator() -> some View {
        let current = viewModel.uiState.step
        let totalSteps = visibleSteps.count
        let currentIndex = visibleSteps.firstIndex(of: current).map { $0 + 1 } ?? 0

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { idx in
                    Capsule()
                        .fill(idx < currentIndex ? Color.blue : Color.gray.opacity(0.25))
                        .frame(height: 4)
                }
            }
            Text(String(localized: "Step \(currentIndex) of \(totalSteps): \(current.displayName)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Steps that are shown for the currently-selected type (skips `selectDevices` when not required).
    private var visibleSteps: [CreateProfileStep] {
        if viewModel.uiState.selectedType?.requiresDevices == false {
            return [.selectType, .selectBundleId, .selectCertificates, .nameAndConfirm, .generated]
        }
        return [.selectType, .selectBundleId, .selectCertificates, .selectDevices, .nameAndConfirm, .generated]
    }

    // MARK: - Step content

    @ViewBuilder
    private func buildStepContent() -> some View {
        switch viewModel.uiState.step {
        case .selectType:         buildTypeStep()
        case .selectBundleId:     buildBundleIdStep()
        case .selectCertificates: buildCertificatesStep()
        case .selectDevices:      buildDevicesStep()
        case .nameAndConfirm:     buildNameAndConfirmStep()
        case .generated:          buildGeneratedStep()
        }
    }

    // MARK: - Step 1: Type

    private func buildTypeStep() -> some View {
        List {
            ForEach(ProfileTypeSection.allCases) { section in
                let typesInSection = ProfileTypeCatalog.all.filter { $0.section == section }
                if !typesInSection.isEmpty {
                    Section {
                        ForEach(typesInSection) { option in
                            Button {
                                viewModel.selectType(option)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text(section.displayName)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Bundle ID

    private func buildBundleIdStep() -> some View {
        VStack(spacing: 0) {
            List {
                Section { buildSelectedTypeRow() } header: { Text(String(localized: "Type")) }

                Section {
                    Toggle(String(localized: "Show all bundle IDs"), isOn: $viewModel.uiState.showAllResources)
                        .font(.subheadline)
                }

                if viewModel.uiState.isLoadingResources && viewModel.uiState.bundleIds.isEmpty {
                    Section { ProgressView() }
                } else if viewModel.uiState.filteredBundleIds.isEmpty {
                    Section {
                        Text(String(localized: "No bundle IDs available for this profile type."))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(viewModel.uiState.filteredBundleIds) { bundle in
                            Button {
                                viewModel.selectBundleId(bundle)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bundle.name)
                                            .foregroundStyle(.primary)
                                            .fontWeight(.medium)
                                        Text(bundle.identifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text(String(localized: "Choose a Bundle ID"))
                    }
                }
            }

            buildBackButton()
        }
    }

    // MARK: - Step 3: Certificates

    private func buildCertificatesStep() -> some View {
        VStack(spacing: 0) {
            List {
                Section { buildSelectedTypeRow() } header: { Text(String(localized: "Type")) }

                Section {
                    Toggle(String(localized: "Show all certificates"), isOn: $viewModel.uiState.showAllResources)
                        .font(.subheadline)
                }

                if viewModel.uiState.filteredCertificates.isEmpty {
                    Section {
                        Text(String(localized: "No matching certificates. Toggle 'Show all' to see every certificate on the account."))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(viewModel.uiState.filteredCertificates) { cert in
                            Button {
                                viewModel.toggleCertificate(id: cert.id)
                            } label: {
                                certificateRow(
                                    cert: cert,
                                    isSelected: viewModel.uiState.selectedCertificateIds.contains(cert.id)
                                )
                            }
                        }
                    } header: {
                        Text(String(localized: "Pick one or more certificates"))
                    } footer: {
                        Text(String(localized: "Only signing certificates appear here; expired ones are hidden unless 'Show all' is on."))
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 12) {
                buildBackInlineButton()
                buildPrimaryButton(
                    title: String(localized: "Continue"),
                    enabled: !viewModel.uiState.selectedCertificateIds.isEmpty
                ) {
                    viewModel.goNextFromCertificates()
                }
            }
            .padding()
        }
    }

    // MARK: - Step 4: Devices

    private func buildDevicesStep() -> some View {
        VStack(spacing: 0) {
            List {
                Section { buildSelectedTypeRow() } header: { Text(String(localized: "Type")) }

                Section {
                    Toggle(String(localized: "Show all devices"), isOn: $viewModel.uiState.showAllResources)
                        .font(.subheadline)
                }

                if viewModel.uiState.filteredDevices.isEmpty {
                    Section {
                        Text(String(localized: "No devices registered for this platform."))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        HStack {
                            Button(String(localized: "Select All")) {
                                for d in viewModel.uiState.filteredDevices {
                                    if !viewModel.uiState.selectedDeviceIds.contains(d.id) {
                                        viewModel.toggleDevice(id: d.id)
                                    }
                                }
                            }
                            Spacer()
                            Button(String(localized: "Deselect All"), role: .destructive) {
                                viewModel.uiState.selectedDeviceIds.removeAll()
                            }
                        }
                        .font(.subheadline)

                        ForEach(viewModel.uiState.filteredDevices) { device in
                            Button {
                                viewModel.toggleDevice(id: device.id)
                            } label: {
                                multiSelectRow(
                                    isSelected: viewModel.uiState.selectedDeviceIds.contains(device.id),
                                    title: device.name,
                                    subtitle: "\(device.deviceClassDisplayName)\(device.udid.map { " · \($0)" } ?? "")"
                                )
                            }
                        }
                    } header: {
                        Text(String(localized: "Pick devices"))
                    } footer: {
                        Text(String(localized: "Development and Ad Hoc profiles must include at least one device."))
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 12) {
                buildBackInlineButton()
                buildPrimaryButton(
                    title: String(localized: "Continue"),
                    enabled: !viewModel.uiState.selectedDeviceIds.isEmpty
                ) {
                    viewModel.goNextFromDevices()
                }
            }
            .padding()
        }
    }

    // MARK: - Step 5: Name & Confirm

    private func buildNameAndConfirmStep() -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField(String(localized: "Profile name"), text: $viewModel.uiState.name)
                        .autocorrectionDisabled()
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isNameFieldFocused = false }
                } header: {
                    Text(String(localized: "Name"))
                } footer: {
                    Text(String(localized: "A short, descriptive name (e.g. \"MyApp Development\")."))
                        .font(.caption)
                }

                Section {
                    summaryRow(label: String(localized: "Type"), value: viewModel.uiState.selectedType?.displayName ?? "—")
                    summaryRow(label: String(localized: "Bundle ID"), value: viewModel.uiState.selectedBundleId?.identifier ?? "—")
                    summaryRow(label: String(localized: "Certificates"), value: "\(viewModel.uiState.selectedCertificateIds.count)")
                    if viewModel.uiState.selectedType?.requiresDevices == true {
                        summaryRow(label: String(localized: "Devices"), value: "\(viewModel.uiState.selectedDeviceIds.count)")
                    }
                } header: {
                    Text(String(localized: "Summary"))
                }
            }

            HStack(spacing: 12) {
                buildBackInlineButton()
                buildPrimaryButton(
                    title: viewModel.uiState.isCreating
                        ? String(localized: "Creating…")
                        : String(localized: "Create Profile"),
                    enabled: canSubmit && !viewModel.uiState.isCreating
                ) {
                    isNameFieldFocused = false
                    Task { await viewModel.submit() }
                }
            }
            .padding()
        }
    }

    private var canSubmit: Bool {
        !viewModel.uiState.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        viewModel.uiState.selectedBundleId != nil &&
        !viewModel.uiState.selectedCertificateIds.isEmpty &&
        (viewModel.uiState.selectedType?.requiresDevices != true || !viewModel.uiState.selectedDeviceIds.isEmpty)
    }

    // MARK: - Step 6: Generated

    @ViewBuilder
    private func buildGeneratedStep() -> some View {
        if let profile = viewModel.uiState.createdProfile {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Profile Created"))
                                .font(.headline)
                            Text(profile.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    summaryRow(label: String(localized: "Type"), value: profile.typeDisplayName)
                    if let uuid = profile.uuid {
                        summaryRow(label: String(localized: "UUID"), value: uuid)
                    }
                    if let expiration = profile.expirationDate {
                        summaryRow(
                            label: String(localized: "Expiration"),
                            value: expiration.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    summaryRow(label: String(localized: "ID"), value: profile.id)
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
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Shared bits

    private func buildSelectedTypeRow() -> some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.blue)
            Text(viewModel.uiState.selectedType?.displayName ?? "—")
                .font(.subheadline)
        }
    }

    private func certificateRow(cert: CertificateModel, isSelected: Bool) -> some View {
        let expirationText: String? = cert.expirationDate.map {
            cert.isExpired
                ? String(localized: "Expired \($0.formatted(date: .abbreviated, time: .omitted))")
                : String(localized: "Expires \($0.formatted(date: .abbreviated, time: .omitted))")
        }

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.blue : Color.gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(cert.displayName)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(cert.typeDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if expirationText != nil {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if let expirationText {
                        Text(expirationText)
                            .font(.caption)
                            .foregroundStyle(cert.isExpired ? .red : .secondary)
                    }
                }
                .lineLimit(1)
            }
            Spacer()
        }
    }

    private func multiSelectRow(isSelected: Bool, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.blue : Color.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func buildBackButton() -> some View {
        Button(String(localized: "Back")) {
            viewModel.goBack()
        }
        .foregroundStyle(.secondary)
        .padding()
    }

    private func buildBackInlineButton() -> some View {
        Button(String(localized: "Back")) {
            viewModel.goBack()
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func buildPrimaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Color.blue : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
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
