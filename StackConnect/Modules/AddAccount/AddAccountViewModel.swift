import Foundation
import StackProtocols
import APIProviderFirebase
import APIProviderPlay

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
    var firebaseJSON = ""
    var googlePlayJSON = ""
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
            // Check for duplicate credentials
            if let duplicateError = await checkDuplicateCredentials() {
                uiState.validationError = duplicateError
                uiState.isValidating = false
                return
            }

            let account = AccountModel(
                name: uiState.accountName.trimmingCharacters(in: .whitespaces),
                providerType: uiState.providerType
            )

            switch uiState.providerType {
            case .apple:
                let key = sanitizedPrivateKey(uiState.privateKey)
                let credentials = AppleCredentials(
                    issuerID: uiState.issuerID.trimmingCharacters(in: .whitespaces),
                    privateKeyID: uiState.privateKeyID.trimmingCharacters(in: .whitespaces),
                    privateKey: key
                )

                let connection = AppleAccountConnection(credentials: credentials)
                try await connection.validateCredentials()

                keychain.setObject(credentials, forKey: "credentials.\(account.id)")

            case .firebase:
                let json = uiState.firebaseJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !json.isEmpty else {
                    uiState.validationError = String(localized: "Service Account JSON is required.")
                    uiState.isValidating = false
                    return
                }

                guard let jsonData = json.data(using: .utf8) else {
                    uiState.validationError = String(localized: "Invalid JSON format.")
                    uiState.isValidating = false
                    return
                }

                let config = try FirebaseConfiguration(serviceAccountJSON: jsonData)
                let provider = APIProviderFirebase(configuration: config)
                let _ = try await provider.request(FirebaseAPI.v1beta1.projects.get())

                let credentials = FirebaseCredentials(serviceAccountJSON: json)
                keychain.setObject(credentials, forKey: "credentials.\(account.id)")

            case .googlePlay:
                let json = uiState.googlePlayJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !json.isEmpty else {
                    uiState.validationError = String(localized: "Service Account JSON is required.")
                    uiState.isValidating = false
                    return
                }

                guard let jsonData = json.data(using: .utf8) else {
                    uiState.validationError = String(localized: "Invalid JSON format.")
                    uiState.isValidating = false
                    return
                }

                // Validate by parsing the configuration (checks key format)
                let _ = try PlayConfiguration(serviceAccountJSON: jsonData)

                let credentials = GooglePlayCredentials(serviceAccountJSON: json)
                keychain.setObject(credentials, forKey: "credentials.\(account.id)")
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

    // MARK: - Private

    private func sanitizedPrivateKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func checkDuplicateCredentials() async -> String? {
        guard let allAccounts = try? await storage.fetchAll(AccountModel.self) else { return nil }
        let sameTypeAccounts = allAccounts.filter { $0.providerType == uiState.providerType }

        for existing in sameTypeAccounts {
            switch uiState.providerType {
            case .apple:
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newKey = sanitizedPrivateKey(uiState.privateKey)
                    if creds.privateKey == newKey {
                        return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                    }
                }
            case .firebase:
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newJSON = uiState.firebaseJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    if creds.serviceAccountJSON == newJSON {
                        return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                    }
                }
            case .googlePlay:
                if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newJSON = uiState.googlePlayJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    if creds.serviceAccountJSON == newJSON {
                        return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                    }
                }
            }
        }

        return nil
    }
}
