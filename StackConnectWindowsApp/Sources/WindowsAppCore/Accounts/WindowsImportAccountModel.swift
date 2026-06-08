import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import StackCrypto

// Phase 4 · Block F · T-F12 — Import account model for the Windows GUI.
//
// 3-step progressive import: `.selectFile` -> `.enterPassword` -> `.confirmName`.
//
// Reads an `.scexport` file, calls `AccountCrypto.decrypt`, validates the JSON
// contents, checks for duplicate credentials, and saves the account + credentials
// to storage/secrets with `origin = .imported`.
//
// Lives in WindowsAppCore (not the executable) so it can be unit-tested without
// SwiftCrossUI views. Uses `SwiftCrossUI.ObservableObject` / `SwiftCrossUI.Published`
// (fully qualified) to avoid Combine ambiguity on macOS.

// MARK: - Import Step

/// The three progressive steps of the import flow.
public enum ImportStep: Int, Hashable, Sendable {
    case selectFile = 0
    case enterPassword = 1
    case confirmName = 2
}

// MARK: - Model

/// Import model that drives the 3-step import flow. The view binds to the
/// published properties; all mutation logic lives here for testability.
@MainActor
public final class WindowsImportAccountModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// Current step in the import wizard.
    @SwiftCrossUI.Published public private(set) var step: ImportStep = .selectFile

    /// The file path entered/selected by the user.
    @SwiftCrossUI.Published public var filePath: String = ""

    /// The decryption password entered by the user.
    @SwiftCrossUI.Published public var password: String = ""

    /// The account name pre-populated from the file, editable by the user.
    @SwiftCrossUI.Published public var accountName: String = ""

    /// Inline error message shown below the active form field. `nil` = no error.
    @SwiftCrossUI.Published public private(set) var errorMessage: String? = nil

    /// True while an async operation (decrypt, save) is in progress.
    @SwiftCrossUI.Published public private(set) var isProcessing: Bool = false

    /// Set to `true` after a successful import so the view can pop to the list.
    @SwiftCrossUI.Published public private(set) var didFinishImport: Bool = false

    // MARK: - Internal State (parsed from the decrypted JSON)

    /// The parsed provider type, available after a successful decrypt.
    public private(set) var parsedProviderType: ProviderType?

    /// The parsed rules from the file, if present.
    private var parsedRules: AccountRules = AccountRules()

    /// The parsed expiration date from the file, if present.
    private var parsedExpirationDate: Date?

    /// The raw credentials dictionary from the decrypted JSON. Stored as
    /// JSON-encoded Data via `KeyStorable` so that WindowsAppCore does not
    /// need to import the concrete credential types from the executable target.
    private var parsedCredentialsDict: [String: String]?

    /// The expected provider for this import flow. When set, the model validates
    /// that the file's provider type matches (AC-8). Defaults to `.apple` since
    /// the import flow is currently only available for Apple accounts (US-W05 AC-1).
    public let expectedProvider: ProviderType

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let secrets: KeyStorable

    /// Abstraction over file reading so tests can inject fake data without touching
    /// the filesystem.
    private let fileReader: (String) throws -> Data

    // MARK: - Init

    /// - Parameters:
    ///   - expectedProvider: The provider type expected in the `.scexport` file.
    ///   - storage: Persistent storage for `AccountModel`.
    ///   - secrets: Secret store for credentials.
    ///   - fileReader: Closure that reads file data from a path. Defaults to
    ///     `Data(contentsOf:)`. Override in tests to avoid filesystem access.
    public init(
        expectedProvider: ProviderType = .apple,
        storage: PersistentStorable,
        secrets: KeyStorable,
        fileReader: @escaping (String) throws -> Data = { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    ) {
        self.expectedProvider = expectedProvider
        self.storage = storage
        self.secrets = secrets
        self.fileReader = fileReader
    }

    // MARK: - Step Navigation

    /// Validates the current step and advances to the next one.
    /// - Step 1 (selectFile): validates file path is non-empty and readable, then
    ///   moves to `enterPassword`.
    /// - Step 2 (enterPassword): reads the file, decrypts, validates JSON, checks
    ///   provider match, then moves to `confirmName`.
    /// - Step 3 (confirmName): saves account + credentials and sets `didFinishImport`.
    public func advanceStep() async {
        errorMessage = nil

        switch step {
        case .selectFile:
            advanceFromSelectFile()
        case .enterPassword:
            await advanceFromEnterPassword()
        case .confirmName:
            await advanceFromConfirmName()
        }
    }

    /// Goes back one step. Does nothing if already at the first step.
    public func goBack() {
        errorMessage = nil
        switch step {
        case .selectFile:
            break
        case .enterPassword:
            password = ""
            step = .selectFile
        case .confirmName:
            step = .enterPassword
        }
    }

    // MARK: - Step 1: Select File

    private func advanceFromSelectFile() {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)

        // AC-4: empty file path
        guard !trimmed.isEmpty else {
            errorMessage = "File path is required."
            return
        }

        // Validate the file is readable by attempting to read it now.
        // We don't store the data yet — that happens in step 2 alongside
        // decryption — but we confirm the path is valid.
        do {
            _ = try fileReader(trimmed)
        } catch {
            // AC-5: file not readable
            errorMessage = "Failed to read file."
            return
        }

        step = .enterPassword
    }

    // MARK: - Step 2: Enter Password

    private func advanceFromEnterPassword() async {
        let trimmedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)

        isProcessing = true
        defer { isProcessing = false }

        // 1. Read file data
        let fileData: Data
        do {
            fileData = try fileReader(trimmedPath)
        } catch {
            // AC-5
            errorMessage = "Failed to read file."
            return
        }

        // 2. Decrypt (AC-2, AC-6)
        let jsonString: String
        do {
            jsonString = try AccountCrypto.decrypt(data: fileData, password: password)
        } catch {
            // AC-6: wrong password or corrupt file
            errorMessage = "Decryption failed. Check your password and try again."
            return
        }

        // 3. Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            errorMessage = "Decryption failed. Check your password and try again."
            return
        }

        // 4. Validate required fields (AC-7)
        guard let name = dict["name"] as? String, !name.isEmpty else {
            errorMessage = "Missing or invalid 'name' field."
            return
        }

        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            errorMessage = "Missing or invalid 'providerType' field."
            return
        }

        // 5. Provider mismatch check (AC-8)
        if providerType != expectedProvider {
            errorMessage = "This file contains a \(providerType.displayName) account, but you are importing into \(expectedProvider.displayName)."
            return
        }

        // 6. Validate credentials field (AC-7)
        guard let credsDict = dict["credentials"] as? [String: String] else {
            errorMessage = "Missing or invalid 'credentials' field."
            return
        }

        // 7. Validate provider-specific credential fields (AC-7)
        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty else {
                errorMessage = "Missing or invalid 'issuerID' field."
                return
            }
            guard let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty else {
                errorMessage = "Missing or invalid 'privateKeyID' field."
                return
            }
            guard let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                errorMessage = "Missing or invalid 'privateKey' field."
                return
            }
        case .firebase, .googlePlay:
            guard let serviceAccountJSON = credsDict["serviceAccountJSON"], !serviceAccountJSON.isEmpty else {
                errorMessage = "Missing or invalid 'serviceAccountJSON' field."
                return
            }
        }

        // 8. Check for duplicate credentials (AC-9)
        if let duplicateName = await findDuplicateCredentials(providerType: providerType, credentials: credsDict) {
            errorMessage = "An account with these credentials already exists: '\(duplicateName)'."
            return
        }

        // 9. Parse optional rules
        if let rulesDict = dict["rules"] as? [String: [String]] {
            parsedRules = AccountRules(
                apps: rulesDict["apps"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                version: rulesDict["version"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                users: rulesDict["users"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                review: rulesDict["review"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                testFlight: rulesDict["testFlight"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                analytics: rulesDict["analytics"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                provisioning: rulesDict["provisioning"]?.compactMap { AccountPermission(rawValue: $0) } ?? []
            )
        }

        // 10. Parse optional expiration date
        if let expirationRaw = dict["expirationDate"] as? String {
            parsedExpirationDate = ISO8601DateFormatter().date(from: expirationRaw)
        }

        // Store parsed data
        parsedProviderType = providerType
        parsedCredentialsDict = credsDict
        accountName = name

        step = .confirmName
    }

    // MARK: - Step 3: Confirm Name

    private func advanceFromConfirmName() async {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Account name is required."
            return
        }

        guard let providerType = parsedProviderType,
              let credsDict = parsedCredentialsDict else {
            errorMessage = "Internal error. Please go back and try again."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let accountId = UUID().uuidString

        // Store credentials as JSON-encoded Data via KeyStorable.
        // The credential dictionary from the file matches the Codable structure
        // expected by the rest of the app (AppleCredentials, FirebaseCredentials, etc.).
        do {
            let credData = try JSONSerialization.data(withJSONObject: credsDict)
            secrets.set(credData, forKey: "credentials.\(accountId)")
        } catch {
            errorMessage = "Failed to store credentials."
            return
        }

        // Create and save the account model (AC-3: origin = .imported)
        let account = AccountModel(
            id: accountId,
            name: trimmedName,
            providerType: providerType,
            rules: parsedRules,
            origin: .imported,
            expirationDate: parsedExpirationDate
        )

        do {
            try await storage.save(account, id: account.id)
            didFinishImport = true
        } catch {
            // Roll back the credential on save failure
            secrets.removeObject(forKey: "credentials.\(accountId)")
            errorMessage = "Failed to save imported account."
        }
    }

    // MARK: - Duplicate Check

    /// Checks whether any existing account of the same provider type already has
    /// the same credentials. Returns the duplicate account's name if found.
    private func findDuplicateCredentials(
        providerType: ProviderType,
        credentials: [String: String]
    ) async -> String? {
        guard let allAccounts = try? await storage.fetchAll(AccountModel.self) else {
            return nil
        }
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType }

        for existing in sameTypeAccounts {
            guard let existingCredData = secrets.data(forKey: "credentials.\(existing.id)") else {
                continue
            }
            guard let existingDict = try? JSONSerialization.jsonObject(with: existingCredData) as? [String: String] else {
                continue
            }

            switch providerType {
            case .apple:
                if existingDict["privateKey"] == credentials["privateKey"] {
                    return existing.name
                }
            case .firebase, .googlePlay:
                if existingDict["serviceAccountJSON"] == credentials["serviceAccountJSON"] {
                    return existing.name
                }
            }
        }

        return nil
    }
}
