import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AddAccountViewModelProtocol: ObservableObject {
    var uiState: AddAccountUiState { get set }
    func save() async
}

// MARK: - UiState

struct AddAccountUiState {
    var accountName = ""
    var issuerID = ""
    var privateKeyID = ""
    var privateKey = ""
    var isValidating = false
    var validationError: String?
    var isSaved = false
    var providerType: ProviderType
}

// MARK: - Implementation

@MainActor
final class AddAccountViewModel: AddAccountViewModelProtocol {

    @Published var uiState: AddAccountUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AddAccountUiState(providerType: providerType)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func save() async {
        guard !uiState.accountName.trimmingCharacters(in: .whitespaces).isEmpty else {
            uiState.validationError = String(localized: "Account name is required.")
            return
        }

        uiState.isValidating = true
        uiState.validationError = nil

        do {
            let account = AccountModel(
                name: uiState.accountName.trimmingCharacters(in: .whitespaces),
                providerType: uiState.providerType
            )

            switch uiState.providerType {
            case .apple:
                let credentials = AppleCredentials(
                    issuerID: uiState.issuerID.trimmingCharacters(in: .whitespaces),
                    privateKeyID: uiState.privateKeyID.trimmingCharacters(in: .whitespaces),
                    privateKey: uiState.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                let connection = AppleAccountConnection(credentials: credentials)
                try await connection.validateCredentials()

                keychain.setObject(credentials, forKey: "credentials.\(account.id)")

            case .firebase:
                break
            }

            try await storage.save(account, id: account.id)
            uiState.isSaved = true
            Log.print.info("[AddAccount] Account saved: \(account.name)")

        } catch {
            uiState.validationError = error.localizedDescription
            Log.print.error("[AddAccount] Validation failed: \(error.localizedDescription)")
        }

        uiState.isValidating = false
    }
}
