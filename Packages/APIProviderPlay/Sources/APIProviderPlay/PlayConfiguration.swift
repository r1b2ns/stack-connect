import Foundation
import _CryptoExtras

/// Google Service Account credentials parsed from the JSON key file.
public struct PlayServiceAccount: Codable {
    public let type: String
    public let projectId: String
    public let privateKeyId: String
    public let privateKey: String
    public let clientEmail: String
    public let clientId: String
    public let authUri: String
    public let tokenUri: String
    public let authProviderX509CertUrl: String
    public let clientX509CertUrl: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
        case authProviderX509CertUrl = "auth_provider_x509_cert_url"
        case clientX509CertUrl = "client_x509_cert_url"
    }
}

/// Configuration for the Google Play Developer API Provider.
public struct PlayConfiguration {

    /// The service account parsed from the JSON key file.
    public let serviceAccount: PlayServiceAccount

    /// The RSA private key used for signing JWTs.
    let privateKey: _RSA.Signing.PrivateKey

    /// The OAuth2 scopes to request.
    public let scopes: [String]

    /// The token's expiration duration in seconds (max 3600 for Google).
    public let expirationDuration: TimeInterval

    /// Creates a configuration from the raw JSON data of a service account key file.
    public init(
        serviceAccountJSON: Data,
        scopes: [String] = [
            "https://www.googleapis.com/auth/androidpublisher",
            "https://www.googleapis.com/auth/playdeveloperreporting"
        ],
        expirationDuration: TimeInterval = 3600
    ) throws {
        let decoder = JSONDecoder()
        self.serviceAccount = try decoder.decode(PlayServiceAccount.self, from: serviceAccountJSON)
        self.scopes = scopes
        self.expirationDuration = min(expirationDuration, 3600)
        self.privateKey = try Self.loadRSAPrivateKey(from: self.serviceAccount.privateKey)
    }

    /// Creates a configuration from a parsed `PlayServiceAccount`.
    public init(
        serviceAccount: PlayServiceAccount,
        scopes: [String] = [
            "https://www.googleapis.com/auth/androidpublisher",
            "https://www.googleapis.com/auth/playdeveloperreporting"
        ],
        expirationDuration: TimeInterval = 3600
    ) throws {
        self.serviceAccount = serviceAccount
        self.scopes = scopes
        self.expirationDuration = min(expirationDuration, 3600)
        self.privateKey = try Self.loadRSAPrivateKey(from: serviceAccount.privateKey)
    }

    // MARK: - Private

    /// Parses the service account's PEM private key. `_RSA.Signing.PrivateKey` accepts the full
    /// PEM (PKCS#8 `BEGIN PRIVATE KEY` or PKCS#1 `BEGIN RSA PRIVATE KEY`) directly, so no manual
    /// header stripping / ASN.1 unwrapping is needed.
    private static func loadRSAPrivateKey(from pemString: String) throws -> _RSA.Signing.PrivateKey {
        do {
            return try _RSA.Signing.PrivateKey(pemRepresentation: pemString)
        } catch {
            throw PlayAuthError.secKeyCreationFailed(error)
        }
    }
}
