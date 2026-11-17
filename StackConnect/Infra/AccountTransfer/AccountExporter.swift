import Foundation

// MARK: - Request

/// What the user chose in `ExportAccountView` for one export.
struct AccountExportRequest {
    let account: AccountModel
    let exportName: String
    let rules: AccountRules
    let password: String
    let expirationDate: Date?
    /// Per-app scope. nil/empty ⇒ all apps (the key is left out of the payload).
    let appsBundles: [String]?
}

// MARK: - Errors

/// Why an export produced no file. Logged only — the UI shows its own generic
/// failure copy — and never carries credential material.
enum AccountExportError: Error, Equatable {
    /// Imported account, or a provider without export (`ProviderType.supportsExport`).
    case notExportable
    /// No credentials in the keychain: the file could never be imported.
    case missingCredentials
    case serializationFailed
}

// MARK: - Protocol

@MainActor
protocol AccountExporting {
    /// Builds, encrypts and writes the account's `.scexport` file.
    /// - Returns: the URL of the written file.
    func export(_ request: AccountExportRequest) throws -> URL
}

// MARK: - Implementation

/// Writes an account's encrypted `.scexport` file: provider credentials from the
/// keychain (`AccountTransferCredentials`) → payload JSON
/// (`AccountExportPayloadBuilder`) → `AccountCrypto` encryption → a neutrally
/// named file in `directory`.
///
/// Shared by Settings › Accounts and Account Settings so both export entry
/// points produce exactly the same file for every provider.
///
/// `@MainActor` because callers are `@MainActor` ViewModels and `KeyStorable` is
/// not `Sendable` (same reasoning as `AccountCascadeDeleter`).
@MainActor
struct AccountExporter: AccountExporting {

    private let keychain: KeyStorable
    private let directory: URL

    init(
        keychain: KeyStorable,
        directory: URL = FileManager.default.temporaryDirectory
    ) {
        self.keychain = keychain
        self.directory = directory
    }

    func export(_ request: AccountExportRequest) throws -> URL {
        let account = request.account

        guard account.isExportable else {
            throw AccountExportError.notExportable
        }
        guard let credentials = AccountTransferCredentials.exportPayload(for: account, keychain: keychain) else {
            throw AccountExportError.missingCredentials
        }
        guard let json = AccountExportPayloadBuilder.makeJSON(
            account: account,
            exportName: request.exportName,
            rules: request.rules,
            expirationDate: request.expirationDate,
            appsBundles: request.appsBundles,
            credentials: credentials
        ) else {
            throw AccountExportError.serializationFailed
        }

        let encryptedData = try AccountCrypto.encrypt(json: json, password: request.password)

        // Neutral filename: avoids leaking the account name / provider in the file name.
        let fileURL = directory.appendingPathComponent("export-\(UUID().uuidString).scexport")
        try encryptedData.write(to: fileURL)
        return fileURL
    }
}
