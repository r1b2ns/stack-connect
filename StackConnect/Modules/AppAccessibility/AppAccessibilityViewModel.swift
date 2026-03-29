import Foundation

// MARK: - Protocol

@MainActor
protocol AppAccessibilityViewModelProtocol: ObservableObject {
    var uiState: AppAccessibilityUiState { get set }
    func load() async
    func save(declaration: AccessibilityDeclarationModel) async
    func publish(declaration: AccessibilityDeclarationModel) async
    func create(deviceFamily: String) async
    func delete(declaration: AccessibilityDeclarationModel) async
}

// MARK: - UiState

struct AppAccessibilityUiState {
    var appId: String
    var account: AccountModel
    var declarations: [AccessibilityDeclarationModel] = []
    var isLoading = false
    var isSaving = false
    var toastMessage: ToastMessage?
    var error: String?
    var editingDeclaration: AccessibilityDeclarationModel?
    var showAddDevice = false
    var confirmDelete: AccessibilityDeclarationModel?

    var availableDeviceFamilies: [String] {
        let existing = Set(declarations.filter { $0.state != "REPLACED" }.map(\.deviceFamily))
        return ["IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION"]
            .filter { !existing.contains($0) }
    }

    var activeDeclarations: [AccessibilityDeclarationModel] {
        declarations
            .filter { $0.state != "REPLACED" }
            .sorted { $0.deviceFamilyDisplayName < $1.deviceFamilyDisplayName }
    }
}

// MARK: - Implementation

@MainActor
final class AppAccessibilityViewModel: AppAccessibilityViewModelProtocol {

    @Published var uiState: AppAccessibilityUiState

    private let keychain: KeyStorable

    init(
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppAccessibilityUiState(appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return
            }

            uiState.declarations = try await connection.fetchAccessibilityDeclarations(appId: uiState.appId)
            Log.print.info("[AppAccessibility] Loaded \(self.uiState.declarations.count) declarations")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppAccessibility] Failed to load: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func save(declaration: AccessibilityDeclarationModel) async {
        uiState.isSaving = true

        do {
            guard let connection = createConnection() else {
                uiState.isSaving = false
                return
            }

            try await connection.updateAccessibilityDeclaration(declaration)

            if let idx = uiState.declarations.firstIndex(where: { $0.id == declaration.id }) {
                uiState.declarations[idx] = declaration
            }

            uiState.editingDeclaration = nil
            uiState.toastMessage = ToastMessage(String(localized: "Accessibility updated"), icon: "accessibility")
            Log.print.info("[AppAccessibility] Saved declaration \(declaration.id)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to save"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[AppAccessibility] Save failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    func publish(declaration: AccessibilityDeclarationModel) async {
        uiState.isSaving = true

        do {
            guard let connection = createConnection() else {
                uiState.isSaving = false
                return
            }

            try await connection.updateAccessibilityDeclaration(declaration, publish: true)

            if let idx = uiState.declarations.firstIndex(where: { $0.id == declaration.id }) {
                uiState.declarations[idx].state = "PUBLISHED"
            }

            uiState.editingDeclaration = nil
            uiState.toastMessage = ToastMessage(String(localized: "Declaration published"), icon: "checkmark.circle.fill")
            Log.print.info("[AppAccessibility] Published declaration \(declaration.id)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to publish"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[AppAccessibility] Publish failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    func create(deviceFamily: String) async {
        uiState.isSaving = true

        do {
            guard let connection = createConnection() else {
                uiState.isSaving = false
                return
            }

            let created = try await connection.createAccessibilityDeclaration(
                appId: uiState.appId,
                deviceFamily: deviceFamily
            )

            uiState.declarations.append(created)
            uiState.showAddDevice = false
            uiState.toastMessage = ToastMessage(String(localized: "Declaration created"), icon: "plus.circle.fill")
            Log.print.info("[AppAccessibility] Created declaration for \(deviceFamily)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to create"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[AppAccessibility] Create failed: \(error.localizedDescription)")
        }

        uiState.isSaving = false
    }

    func delete(declaration: AccessibilityDeclarationModel) async {
        do {
            guard let connection = createConnection() else { return }

            try await connection.deleteAccessibilityDeclaration(id: declaration.id)
            uiState.declarations.removeAll { $0.id == declaration.id }
            uiState.toastMessage = ToastMessage(String(localized: "Declaration deleted"), icon: "trash")
            Log.print.info("[AppAccessibility] Deleted declaration \(declaration.id)")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to delete"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[AppAccessibility] Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
