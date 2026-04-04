import SwiftUI

// MARK: - Factory

@MainActor
struct AccountSettingsViewFactory {
    static func build(account: AccountModel) -> some View {
        AccountSettingsEntry(account: account)
    }
}

// MARK: - Entry

private struct AccountSettingsEntry: View {
    let account: AccountModel

    @StateObject private var viewModel: AccountSettingsViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: AccountSettingsViewModel(account: account))
    }

    var body: some View {
        AccountSettingsView(viewModel: viewModel)
    }
}

// MARK: - Protocol

@MainActor
protocol AccountSettingsViewModelProtocol: ObservableObject {
    var uiState: AccountSettingsUiState { get set }
    func save() async
    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String) -> URL?
}

// MARK: - UiState

struct AccountSettingsUiState {
    var account: AccountModel
    var editingName: String
    var toastMessage: ToastMessage?
}

// MARK: - ViewModel

@MainActor
final class AccountSettingsViewModel: AccountSettingsViewModelProtocol {

    @Published var uiState: AccountSettingsUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AccountSettingsUiState(
            account: account,
            editingName: account.name
        )
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func save() async {
        let trimmed = uiState.editingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let updated = AccountModel(
            id: uiState.account.id,
            name: trimmed,
            providerType: uiState.account.providerType,
            createdAt: uiState.account.createdAt,
            rules: uiState.account.rules,
            origin: uiState.account.origin
        )

        do {
            try await storage.save(updated, id: updated.id)
            uiState.account = updated
            uiState.toastMessage = ToastMessage(String(localized: "Saved"), icon: "checkmark.circle.fill")
            Log.print.info("[AccountSettings] Saved account: \(trimmed)")
        } catch {
            Log.print.error("[AccountSettings] Failed to save: \(error.localizedDescription)")
        }
    }

    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String) -> URL? {
        var exportDict: [String: Any] = [
            "id": uiState.account.id,
            "name": exportName,
            "providerType": uiState.account.providerType.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: uiState.account.createdAt)
        ]

        exportDict["rules"] = [
            "apps": rules.apps.map(\.rawValue),
            "version": rules.version.map(\.rawValue),
            "users": rules.users.map(\.rawValue),
            "review": rules.review.map(\.rawValue),
            "testFlight": rules.testFlight.map(\.rawValue),
            "analytics": rules.analytics.map(\.rawValue)
        ]

        if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") {
            exportDict["credentials"] = [
                "issuerID": creds.issuerID,
                "privateKeyID": creds.privateKeyID,
                "privateKey": creds.privateKey
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let encryptedData = try? AccountCrypto.encrypt(json: json, password: password) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let sanitizedName = exportName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let accountType = uiState.account.providerType.rawValue
        let fileName = "\(sanitizedName)-stackconnect-\(accountType)-\(dateString).scexport"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try encryptedData.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}

// MARK: - View

struct AccountSettingsView<ViewModel: AccountSettingsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    @State private var showExport = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var showNameEdit = false

    private let resources: [AccountRuleResource] = [
        .apps, .version, .review, .testFlight, .analytics, .users
    ]

    var body: some View {
        Form {
            buildInfoSection()
            buildRulesSection()

            if viewModel.uiState.account.isExportable {
                buildExportSection()
            }
        }
        .navigationTitle(String(localized: "Account Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toast(message: $viewModel.uiState.toastMessage)
        .sheet(isPresented: $showExport) {
            ExportAccountView(
                account: viewModel.uiState.account,
                onExport: { name, rules, password in
                    let url = viewModel.exportAccountWithRules(exportName: name, rules: rules, password: password)
                    showExport = false
                    if let url {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            exportFileURL = url
                            showExportShare = true
                        }
                    }
                    return url
                },
                onDismiss: { showExport = false }
            )
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                ShareSheetWrapper(activityItems: [url])
            }
        }
        .alert(
            String(localized: "Edit Name"),
            isPresented: $showNameEdit
        ) {
            TextField(String(localized: "Account Name"), text: $viewModel.uiState.editingName)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Save")) {
                Task { await viewModel.save() }
            }
        } message: {
            Text(String(localized: "Enter a new name for this account."))
        }
    }

    // MARK: - Info Section

    private func buildInfoSection() -> some View {
        Section {
            Button {
                viewModel.uiState.editingName = viewModel.uiState.account.name
                showNameEdit = true
            } label: {
                HStack {
                    Text(String(localized: "Name"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.uiState.account.name)
                        .foregroundStyle(.primary)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            HStack {
                Text(String(localized: "Provider"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.uiState.account.providerType.displayName)
            }

            HStack {
                Text(String(localized: "Origin"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.uiState.account.origin == .created
                     ? String(localized: "Created")
                     : String(localized: "Imported"))
            }

            HStack {
                Text(String(localized: "Created"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.uiState.account.createdAt, style: .date)
            }
        } header: {
            Text(String(localized: "Account"))
        }
    }

    // MARK: - Rules Section

    private func buildRulesSection() -> some View {
        Section {
            ForEach(resources, id: \.self) { resource in
                HStack {
                    Text(resource.displayName)

                    Spacer()

                    let perms = viewModel.uiState.account.rules[resource]
                    if perms.isEmpty {
                        Text(String(localized: "None"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(perms.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.accent)
                    }
                }
            }
        } header: {
            Text(String(localized: "Permissions"))
        }
    }

    // MARK: - Export Section

    private func buildExportSection() -> some View {
        Section {
            Button {
                showExport = true
            } label: {
                Label(String(localized: "Export Account"), systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Share Sheet Wrapper

private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
