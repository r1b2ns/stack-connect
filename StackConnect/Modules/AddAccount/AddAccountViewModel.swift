import Foundation
import StackProtocols
import APIProviderFirebase

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
    var role: AccountRole = .unspecified
}

// MARK: - Implementation

@MainActor
final class AddAccountViewModel: AddAccountViewModelProtocol {

    /// Builds the Google Play connection used to validate a new key against the
    /// live service. Injected so tests never hit the network or the Rust core.
    typealias GooglePlayConnectionFactory = (GooglePlayCredentials) -> any GooglePlayAccountConnecting

    @Published var uiState: AddAccountUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let googlePlayConnectionFactory: GooglePlayConnectionFactory

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        googlePlayConnectionFactory: @escaping GooglePlayConnectionFactory = { GooglePlayAccountConnection(credentials: $0) }
    ) {
        self.uiState = AddAccountUiState(providerType: providerType)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.googlePlayConnectionFactory = googlePlayConnectionFactory
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

            // The role picker is hidden for providers without roles (Google
            // Play): those accounts always keep the default role.
            let account = AccountModel(
                name: uiState.accountName.trimmingCharacters(in: .whitespaces),
                providerType: uiState.providerType,
                role: uiState.providerType.supportsAccountRole ? uiState.role : .unspecified
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

                // Offline format check first (empty / malformed / not a service
                // account), then the live check: token exchange + Play Developer
                // Reporting API through the Rust core.
                _ = try GooglePlayServiceAccount(json: json)

                // Storage format unchanged (plan D2): the whole JSON file.
                let credentials = GooglePlayCredentials(serviceAccountJSON: json)
                try await googlePlayConnectionFactory(credentials).validateCredentials()

                keychain.setObject(credentials, forKey: "credentials.\(account.id)")
            }

            try await storage.save(account, id: account.id)
            uiState.isSaved = true
            Log.print.info("[AddAccount] Account saved: \(account.name)")

        } catch {
            uiState.validationError = friendlyMessage(for: error)
            Log.print.error("[AddAccount] Validation failed: \(error.localizedDescription)")
        }

        uiState.isValidating = false
    }

    // MARK: - Private

    private func friendlyMessage(for error: Error) -> String {
        switch uiState.providerType {
        case .googlePlay:
            return GooglePlayErrorTranslator.friendlyMessage(for: error)
        case .apple, .firebase:
            return error.localizedDescription
        }
    }

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
        let newName = uiState.accountName.trimmingCharacters(in: .whitespaces)

        // Google Play: same service account = same `client_email` (plan D4), so a
        // re-formatted or re-downloaded key of that account is caught too. An
        // unparseable new key is not a duplicate: save() reports why.
        if uiState.providerType == .googlePlay {
            guard let existing = GooglePlayDuplicateAccountFinder.existingAccount(
                matching: uiState.googlePlayJSON,
                in: sameTypeAccounts,
                keychain: keychain
            ) else {
                return nil
            }
            return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
        }

        for existing in sameTypeAccounts {
            switch uiState.providerType {
            case .apple:
                // Same team key may be registered again under a different name/role.
                // Only block an EXACT duplicate: same private key AND same account name.
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)") {
                    let newKey = sanitizedPrivateKey(uiState.privateKey)
                    if creds.privateKey == newKey && existing.name == newName {
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
                break // Handled above.
            }
        }

        return nil
    }
}
