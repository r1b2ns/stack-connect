import SwiftUI
import StackProtocols

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
    func saveDeveloperId() async
    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL?
    func appsForExport() async -> [ExportableApp]
}

// MARK: - UiState

struct AccountSettingsUiState {
    var account: AccountModel
    var editingName: String
    var editingRole: AccountRole
    /// Google Play developer ID being edited (digits or a Play Console URL).
    var editingDeveloperId = ""
    var toastMessage: ToastMessage?
}

// MARK: - ViewModel

@MainActor
final class AccountSettingsViewModel: AccountSettingsViewModelProtocol {

    @Published var uiState: AccountSettingsUiState

    private let storage: PersistentStorable
    private let exporter: AccountExporting
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        exporter: AccountExporting? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = AccountSettingsUiState(
            account: account,
            editingName: account.name,
            editingRole: account.role
        )
        self.storage = storage ?? SwiftDataStorable.shared
        self.exporter = exporter ?? AccountExporter(keychain: keychain)
        self.analytics = analytics
    }

    func save() async {
        let trimmed = uiState.editingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // `updating` keeps every other field — notably the per-app scope. The
        // role is only editable for providers that have one (not Google Play).
        let role = uiState.account.providerType.supportsAccountRole ? uiState.editingRole : uiState.account.role
        let updated = uiState.account.updating(name: trimmed, role: role)

        do {
            try await storage.save(updated, id: updated.id)
            uiState.account = updated
            uiState.toastMessage = ToastMessage(String(localized: "Saved"), icon: "checkmark.circle.fill")
            Log.print.info("[AccountSettings] Saved account: \(trimmed)")
            analytics.track(.action(.saveAccount, on: .accountSettings, result: .success))
        } catch {
            Log.print.error("[AccountSettings] Failed to save: \(error.localizedDescription)")
            analytics.track(.action(.saveAccount, on: .accountSettings, result: .failure))
        }
    }

    /// Saves the Google Play developer ID (plan U3); an empty field clears it.
    func saveDeveloperId() async {
        let input = uiState.editingDeveloperId
        guard GooglePlayDeveloperId.isAcceptable(input) else {
            // The input isn't known to be an ID (it may be any pasted text): private.
            Log.print.error("[AccountSettings] Developer ID refused by the normalizer — length: \(input.count, privacy: .public), input: \"\(input)\"")
            uiState.toastMessage = ToastMessage(GooglePlayDeveloperId.invalidMessage, icon: "exclamationmark.triangle.fill")
            return
        }
        let developerId = GooglePlayDeveloperId.normalized(input)
        let updated = uiState.account.updating(googlePlayDeveloperId: .some(developerId))
        do {
            try await storage.save(updated, id: updated.id)
            uiState.account = updated
            uiState.toastMessage = ToastMessage(String(localized: "Saved"), icon: "checkmark.circle.fill")
            analytics.track(.action(.saveAccount, on: .accountSettings, result: .success))
        } catch {
            Log.print.error("[AccountSettings] Failed to save the developer ID \"\(developerId ?? "", privacy: .public)\": \(error.localizedDescription, privacy: .public)")
            uiState.toastMessage = ToastMessage(
                String(localized: "The Developer ID couldn't be saved. Try again.") + "\n" + error.localizedDescription,
                icon: "exclamationmark.triangle.fill"
            )
            analytics.track(.action(.saveAccount, on: .accountSettings, result: .failure))
        }
    }

    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
        let url = makeExportFile(exportName: exportName, rules: rules, password: password, expirationDate: expirationDate, appsBundles: appsBundles)
        analytics.track(.action(
            .exportAccount,
            on: .exportAccount,
            result: url == nil ? .failure : .success,
            parameters: AnalyticsParameterKey.exportParameters(expirationDate: expirationDate, appsBundles: appsBundles)
        ))
        return url
    }

    private func makeExportFile(exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
        do {
            return try exporter.export(AccountExportRequest(
                account: uiState.account,
                exportName: exportName,
                rules: rules,
                password: password,
                expirationDate: expirationDate,
                appsBundles: appsBundles
            ))
        } catch {
            Log.print.error("[AccountSettings] Export failed: \(String(describing: error))")
            return nil
        }
    }

    /// Apps belonging to this account, sorted by name, for the export scope picker.
    func appsForExport() async -> [ExportableApp] {
        await ExportableAppsLoader.apps(for: uiState.account, storage: storage)
    }
}

// MARK: - View

struct AccountSettingsView<ViewModel: AccountSettingsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    @State private var showExport = false
    @State private var shareItem: ShareableFileURL?
    @State private var showNameEdit = false
    @State private var showDeveloperIdEdit = false

    /// Only the rule resources that apply to the account's provider.
    private var resources: [AccountRuleResource] {
        viewModel.uiState.account.ruleResources
    }

    var body: some View {
        Form {
            buildInfoSection()

            if !resources.isEmpty {
                buildRulesSection()
            }

            if viewModel.uiState.account.isExportable {
                buildExportSection()
            }
        }
        .navigationTitle(String(localized: "Account Settings"))
        .trackScreen(.accountSettings)
        .navigationBarTitleDisplayMode(.inline)
        .toast(message: $viewModel.uiState.toastMessage)
        .sheet(isPresented: $showExport) {
            ExportAccountView(
                account: viewModel.uiState.account,
                loadApps: { await viewModel.appsForExport() },
                onExport: { name, rules, password, expirationDate, appsBundles in
                    let url = viewModel.exportAccountWithRules(exportName: name, rules: rules, password: password, expirationDate: expirationDate, appsBundles: appsBundles)
                    showExport = false
                    if let url {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            shareItem = ShareableFileURL(url: url)
                        }
                    }
                    return url
                },
                onDismiss: { showExport = false }
            )
        }
        .sheet(item: $shareItem) { item in
            ShareSheetWrapper(activityItems: [item.url])
        }
        .alert(
            String(localized: "Edit Name"),
            isPresented: $showNameEdit
        ) {
            TextField(String(localized: "Account Name"), text: $viewModel.uiState.editingName)
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .accountSettings, role: .cancel) {}
            StackTrackedButton(String(localized: "Save"), button: .save, on: .accountSettings) {
                Task { await viewModel.save() }
            }
        } message: {
            Text(String(localized: "Enter a new name for this account."))
        }
        .alert(
            String(localized: "Developer ID"),
            isPresented: $showDeveloperIdEdit
        ) {
            TextField(String(localized: "Developer ID"), text: $viewModel.uiState.editingDeveloperId)
                .keyboardType(.numbersAndPunctuation)
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .accountSettings, role: .cancel) {}
            StackTrackedButton(String(localized: "Save"), button: .save, on: .accountSettings) {
                Task { await viewModel.saveDeveloperId() }
            }
        } message: {
            Text("The number in Play Console › Settings › Developer account. The Users tab needs it.")
        }
    }

    // MARK: - Info Section

    private func buildInfoSection() -> some View {
        Section {
            StackTrackedButton(.editName, on: .accountSettings) {
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

            if viewModel.uiState.account.providerType.supportsAccountRole {
                buildRolePicker()
            }

            if viewModel.uiState.account.providerType == .googlePlay {
                buildDeveloperIdRow()
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
                Text(viewModel.uiState.account.createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let expirationDate = viewModel.uiState.account.expirationDate {
                HStack {
                    Text(String(localized: "Expiration Date"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(expirationDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(viewModel.uiState.account.isExpired ? .red : .primary)
                }
            }
        } header: {
            Text(String(localized: "Account"))
        }
    }

    /// Google Play developer ID (plan U3), editable for created and imported accounts.
    private func buildDeveloperIdRow() -> some View {
        StackTrackedButton(.editDeveloperId, on: .accountSettings) {
            viewModel.uiState.editingDeveloperId = viewModel.uiState.account.googlePlayDeveloperId ?? ""
            showDeveloperIdEdit = true
        } label: {
            HStack {
                Text(String(localized: "Developer ID"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.uiState.account.googlePlayDeveloperId ?? String(localized: "Not set"))
                    .foregroundStyle(viewModel.uiState.account.googlePlayDeveloperId == nil ? .secondary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    /// App Store Connect role. Not shown for providers without roles (Google Play).
    private func buildRolePicker() -> some View {
        Picker(
            String(localized: "Role"),
            selection: $viewModel.uiState.editingRole
        ) {
            ForEach(AccountRole.allCases, id: \.self) { role in
                Text(role.displayName).tag(role)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: viewModel.uiState.editingRole) { _, _ in
            Task { await viewModel.save() }
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
            StackTrackedButton(.export, on: .accountSettings) {
                showExport = true
            } label: {
                Label(String(localized: "Export Account"), systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Shareable File URL

struct ShareableFileURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet Wrapper

private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            for case let url as URL in activityItems where url.isFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
