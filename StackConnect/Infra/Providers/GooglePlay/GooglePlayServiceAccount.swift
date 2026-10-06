import Foundation

/// The parts of a Google Cloud service-account JSON key the app needs to talk to
/// Google Play through the Rust core.
///
/// The Keychain (and `.scexport`) keep the whole file as
/// `GooglePlayCredentials.serviceAccountJSON` (plan D2 — storage format
/// unchanged); this type is the host-side JSON → fields conversion the core
/// expects (`clientEmail`, `privateKeyId`, `privateKey`).
///
/// `privateKey` is the PEM exactly as decoded from JSON (real newlines). The core
/// accepts PKCS#8 or PKCS#1, raw or JSON-escaped, so no sanitising happens here.
///
/// Security: never log `privateKey` (or the raw JSON). `clientEmail` is not a
/// secret — it is how the account shows up in Play Console › Users and permissions.
struct GooglePlayServiceAccount: Equatable, Sendable {

    let clientEmail: String
    let privateKeyId: String
    let privateKey: String
    let projectId: String?

    /// The only `type` a service-account key file declares.
    static let serviceAccountType = "service_account"

    /// Parses a service-account key file.
    ///
    /// - Throws: `ParseError` when the text is empty, not a JSON object, not a
    ///   service-account key, or misses one of the required fields.
    init(json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }

        let file: KeyFile
        do {
            file = try JSONDecoder().decode(KeyFile.self, from: Data(trimmed.utf8))
        } catch {
            // Deliberately not logging `error`: decoding errors can echo the
            // offending JSON fragment, which may be key material.
            throw ParseError.malformedJSON
        }

        if let type = file.type, type != Self.serviceAccountType {
            throw ParseError.unsupportedType(type)
        }

        guard let clientEmail = Self.nonBlank(file.clientEmail) else {
            throw ParseError.missingField(.clientEmail)
        }
        guard clientEmail.contains("@") else {
            throw ParseError.invalidClientEmail
        }
        guard let privateKeyId = Self.nonBlank(file.privateKeyId) else {
            throw ParseError.missingField(.privateKeyId)
        }
        // Only blank-checked: the PEM is passed to the core byte-for-byte.
        guard let privateKey = file.privateKey,
              !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.missingField(.privateKey)
        }

        self.clientEmail = clientEmail
        self.privateKeyId = privateKeyId
        self.privateKey = privateKey
        self.projectId = Self.nonBlank(file.projectId)
    }

    /// Convenience for the stored credentials (`GooglePlayCredentials`).
    init(credentials: GooglePlayCredentials) throws {
        try self.init(json: credentials.serviceAccountJSON)
    }

    // MARK: - Private

    /// Wire shape of the key file. Every field is optional so a missing one maps
    /// to a precise `ParseError.missingField` instead of a generic decode failure.
    private struct KeyFile: Decodable {
        let type: String?
        let clientEmail: String?
        let privateKeyId: String?
        let privateKey: String?
        let projectId: String?

        enum CodingKeys: String, CodingKey {
            case type
            case clientEmail = "client_email"
            case privateKeyId = "private_key_id"
            case privateKey = "private_key"
            case projectId = "project_id"
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Errors

extension GooglePlayServiceAccount {

    /// Why a pasted / imported key file can't be used. `errorDescription` is
    /// user-facing copy (see also `GooglePlayErrorTranslator`).
    enum ParseError: LocalizedError, Equatable {
        case empty
        case malformedJSON
        /// The JSON declares a `type` other than `service_account` (e.g. an
        /// OAuth client or `authorized_user` file).
        case unsupportedType(String)
        case missingField(Field)
        case invalidClientEmail

        /// Required key-file fields, named as they appear in the JSON.
        enum Field: String {
            case clientEmail = "client_email"
            case privateKeyId = "private_key_id"
            case privateKey = "private_key"
        }

        var errorDescription: String? {
            switch self {
            case .empty:
                return String(localized: "Service Account JSON is required.")
            case .malformedJSON:
                return String(localized: "This isn't a valid JSON file. Paste or import the full service account key downloaded from Google Cloud.")
            case .unsupportedType:
                return String(localized: "This JSON isn't a service account key. In Google Cloud, open IAM & Admin › Service Accounts, pick the account and create a JSON key under Keys.")
            case .missingField(let field):
                return String(localized: "The service account key is missing \"\(field.rawValue)\". Download a new JSON key from Google Cloud.")
            case .invalidClientEmail:
                return String(localized: "The service account e-mail (client_email) in this key is invalid.")
            }
        }
    }
}
