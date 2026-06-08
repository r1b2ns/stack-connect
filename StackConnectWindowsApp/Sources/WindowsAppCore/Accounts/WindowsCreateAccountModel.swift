import Foundation
import SwiftCrossUI
import StackProtocols
import StackHomeCore

// Phase 4 · Block F · T-F09 — Create account model for the Windows app.
//
// SwiftCrossUI `ObservableObject` that drives the create-account form for both
// Apple and Firebase provider types. Handles field validation, PEM header
// sanitization, duplicate credential detection, and persists the account to
// SQLite + credentials to the Windows Credential Manager.

@MainActor
public final class WindowsCreateAccountModel: SwiftCrossUI.ObservableObject {

    // MARK: - Apple form fields

    @SwiftCrossUI.Published public var accountName: String = ""
    @SwiftCrossUI.Published public var issuerID: String = ""
    @SwiftCrossUI.Published public var privateKeyID: String = ""
    @SwiftCrossUI.Published public var privateKey: String = ""

    // MARK: - Firebase form fields

    @SwiftCrossUI.Published public var serviceAccountJSON: String = ""

    // MARK: - State

    @SwiftCrossUI.Published public var isSaving: Bool = false
    @SwiftCrossUI.Published public var errorMessage: String? = nil
    @SwiftCrossUI.Published public var isSaved: Bool = false

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let secrets: KeyStorable
    private let providerType: ProviderType

    public init(
        providerType: ProviderType,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        self.providerType = providerType
        self.storage = storage
        self.secrets = secrets
    }

    // MARK: - Save Apple Account (US-W03)

    /// Validates Apple account fields, sanitizes the PEM key, checks for
    /// duplicate credentials, and persists the account + credentials.
    public func saveAppleAccount() async {
        // AC-4: Account Name empty -> inline error
        guard !accountName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Account name is required."
            return
        }

        // AC-2: All four fields non-empty validation
        guard !issuerID.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Issuer ID is required."
            return
        }

        guard !privateKeyID.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Private Key ID is required."
            return
        }

        guard !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Private Key is required."
            return
        }

        // AC-2: Show loading, disable form
        isSaving = true
        errorMessage = nil

        do {
            // AC-7: Sanitize PEM headers/footer before storing
            let sanitizedKey = sanitizedPrivateKey(privateKey)

            // AC-5: Duplicate private key detection
            if let duplicateName = try await findDuplicateAppleCredentials(sanitizedKey: sanitizedKey) {
                errorMessage = "An account with these credentials already exists: \"\(duplicateName)\"."
                isSaving = false
                return
            }

            // AC-3: Build and persist the account
            let account = AccountModel(
                name: accountName.trimmingCharacters(in: .whitespaces),
                providerType: self.providerType
            )

            let credentials = AppleCredentials(
                issuerID: issuerID.trimmingCharacters(in: .whitespaces),
                privateKeyID: privateKeyID.trimmingCharacters(in: .whitespaces),
                privateKey: sanitizedKey
            )

            // 1. Persist account to SQLite first (can throw)
            try await storage.save(account, id: account.id)

            // 2. Only if SQLite succeeded, write credentials
            secrets.setObject(credentials, forKey: "credentials.\(account.id)")

            isSaving = false
            isSaved = true

        } catch {
            // AC-6: Save failure -> inline error with description, form re-enabled
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    // MARK: - Save Firebase Account (US-W04)

    /// Validates Firebase account fields (JSON non-empty + parseable), checks for
    /// duplicate credentials, and persists the account + credentials.
    public func saveFirebaseAccount() async {
        // Account name is required for Firebase too
        guard !accountName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Account name is required."
            return
        }

        let trimmedJSON = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        // AC-2: JSON empty -> inline error
        guard !trimmedJSON.isEmpty else {
            errorMessage = "Service Account JSON is required."
            return
        }

        // AC-3: Invalid JSON -> inline error
        guard let jsonData = trimmedJSON.data(using: .utf8),
              isValidJSON(jsonData) else {
            errorMessage = "Invalid JSON format."
            return
        }

        // Show loading, disable form
        isSaving = true
        errorMessage = nil

        do {
            // AC-5: Duplicate JSON detection
            if let duplicateName = try await findDuplicateFirebaseCredentials(json: trimmedJSON) {
                errorMessage = "An account with these credentials already exists: \"\(duplicateName)\"."
                isSaving = false
                return
            }

            // AC-4: Build and persist the account
            let account = AccountModel(
                name: accountName.trimmingCharacters(in: .whitespaces),
                providerType: self.providerType
            )

            let credentials = FirebaseCredentials(serviceAccountJSON: trimmedJSON)

            // 1. Persist account to SQLite first (can throw)
            try await storage.save(account, id: account.id)

            // 2. Only if SQLite succeeded, write credentials
            secrets.setObject(credentials, forKey: "credentials.\(account.id)")

            isSaving = false
            isSaved = true

        } catch {
            // Save failure -> inline error with description, form re-enabled
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    // MARK: - Form Completion (AC-2)

    /// Whether all four Apple form fields are non-empty after trimming.
    /// Uses `.whitespaces` for text fields and `.whitespacesAndNewlines` for the
    /// Private Key TextEditor (intentional: editor content may contain newlines).
    public var isFormComplete: Bool {
        !accountName.trimmingCharacters(in: .whitespaces).isEmpty
            && !issuerID.trimmingCharacters(in: .whitespaces).isEmpty
            && !privateKeyID.trimmingCharacters(in: .whitespaces).isEmpty
            && !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - File Loading

    /// Reads the file at the given path and sets its content as the Private Key.
    /// Sets `errorMessage` on failure (file not readable or not valid UTF-8).
    public func loadPrivateKeyFromFile(at path: String) {
        guard let data = FileManager.default.contents(atPath: path) else {
            errorMessage = "Could not read file at path: \(path)"
            return
        }
        guard let content = String(data: data, encoding: .utf8) else {
            errorMessage = "File is not valid UTF-8: \(path)"
            return
        }
        privateKey = content
    }

    // MARK: - PEM Sanitization (AC-7)

    /// Strips ALL PEM header/footer lines (any line starting with "-----"),
    /// carriage returns (Windows `\r\n`), and remaining whitespace from a private
    /// key string. Returns the raw base64 content suitable for credential storage.
    /// Handles both `BEGIN PRIVATE KEY` and `BEGIN EC PRIVATE KEY` variants.
    public func sanitizedPrivateKey(_ key: String) -> String {
        key
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Duplicate Detection

    /// Checks all existing Apple accounts for a matching private key.
    /// Returns the name of the duplicate account if found, nil otherwise.
    private func findDuplicateAppleCredentials(sanitizedKey: String) async throws -> String? {
        let allAccounts = try await storage.fetchAll(AccountModel.self)
        let appleAccounts = allAccounts.filter { $0.providerType == .apple }

        for existing in appleAccounts {
            if let creds: AppleCredentials = secrets.object(forKey: "credentials.\(existing.id)") {
                if creds.privateKey == sanitizedKey {
                    return existing.name
                }
            }
        }

        return nil
    }

    /// Checks all existing Firebase accounts for a matching service account JSON.
    /// Returns the name of the duplicate account if found, nil otherwise.
    private func findDuplicateFirebaseCredentials(json: String) async throws -> String? {
        let allAccounts = try await storage.fetchAll(AccountModel.self)
        let firebaseAccounts = allAccounts.filter { $0.providerType == .firebase }

        for existing in firebaseAccounts {
            if let creds: FirebaseCredentials = secrets.object(forKey: "credentials.\(existing.id)") {
                if creds.serviceAccountJSON == json {
                    return existing.name
                }
            }
        }

        return nil
    }

    // MARK: - JSON Validation

    /// Validates that the given data is parseable as JSON.
    private func isValidJSON(_ data: Data) -> Bool {
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
}
