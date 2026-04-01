import Foundation
import Security

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

    /// The RSA private key reference for signing JWTs.
    let privateKey: SecKey

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

    private static func loadRSAPrivateKey(from pemString: String) throws -> SecKey {
        let stripped = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard var keyData = Data(base64Encoded: stripped) else {
            throw PlayAuthError.invalidPrivateKey
        }

        keyData = Self.stripPKCS8HeaderIfNeeded(keyData)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw PlayAuthError.secKeyCreationFailed(error as Swift.Error)
            }
            throw PlayAuthError.invalidPrivateKey
        }

        return secKey
    }

    private static func stripPKCS8HeaderIfNeeded(_ data: Data) -> Data {
        guard data.count > 26, data[0] == 0x30 else { return data }

        var index = 0

        guard readASN1TagAndLength(data, index: &index) != nil else { return data }

        guard index < data.count, data[index] == 0x02 else { return data }
        guard skipASN1Element(data, index: &index) else { return data }

        guard index < data.count, data[index] == 0x30 else { return data }
        guard skipASN1Element(data, index: &index) else { return data }

        guard index < data.count, data[index] == 0x04 else { return data }
        guard let octetLength = readASN1TagAndLength(data, index: &index) else { return data }

        guard index + octetLength <= data.count else { return data }
        return data.subdata(in: index..<(index + octetLength))
    }

    private static func readASN1TagAndLength(_ data: Data, index: inout Int) -> Int? {
        guard index < data.count else { return nil }
        index += 1
        return readASN1Length(data, index: &index)
    }

    private static func skipASN1Element(_ data: Data, index: inout Int) -> Bool {
        guard let length = readASN1TagAndLength(data, index: &index) else { return false }
        index += length
        return index <= data.count
    }

    private static func readASN1Length(_ data: Data, index: inout Int) -> Int? {
        guard index < data.count else { return nil }
        let first = data[index]
        index += 1
        if first & 0x80 == 0 {
            return Int(first)
        }
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0, numBytes <= 4, index + numBytes <= data.count else { return nil }
        var length = 0
        for _ in 0..<numBytes {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}
