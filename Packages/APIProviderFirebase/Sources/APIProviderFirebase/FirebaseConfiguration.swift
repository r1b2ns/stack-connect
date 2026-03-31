import Foundation
import Security

/// Firebase Service Account credentials parsed from the JSON key file.
public struct FirebaseServiceAccount: Codable {
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

/// Configuration for the Firebase API Provider.
public struct FirebaseConfiguration {

    /// The service account parsed from the JSON key file.
    public let serviceAccount: FirebaseServiceAccount

    /// The RSA private key reference for signing JWTs.
    let privateKey: SecKey

    /// The OAuth2 scopes to request.
    public let scopes: [String]

    /// The token's expiration duration in seconds (max 3600 for Google).
    public let expirationDuration: TimeInterval

    /// Creates a configuration from the raw JSON data of a service account key file.
    ///
    /// - Parameters:
    ///   - serviceAccountJSON: The raw JSON data from the downloaded service account key file.
    ///   - scopes: OAuth2 scopes. Defaults to Firebase + Cloud Platform scopes.
    ///   - expirationDuration: Token expiration in seconds. Max 3600. Defaults to 3600.
    public init(
        serviceAccountJSON: Data,
        scopes: [String] = [
            "https://www.googleapis.com/auth/firebase",
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/analytics.readonly",
            "https://www.googleapis.com/auth/firebase.messaging"
        ],
        expirationDuration: TimeInterval = 3600
    ) throws {
        let decoder = JSONDecoder()
        self.serviceAccount = try decoder.decode(FirebaseServiceAccount.self, from: serviceAccountJSON)
        self.scopes = scopes
        self.expirationDuration = min(expirationDuration, 3600)
        self.privateKey = try Self.loadRSAPrivateKey(from: self.serviceAccount.privateKey)
    }

    /// Creates a configuration from a parsed `FirebaseServiceAccount`.
    public init(
        serviceAccount: FirebaseServiceAccount,
        scopes: [String] = [
            "https://www.googleapis.com/auth/firebase",
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/analytics.readonly",
            "https://www.googleapis.com/auth/firebase.messaging"
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
        // Strip PEM headers/footers and whitespace
        let stripped = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard var keyData = Data(base64Encoded: stripped) else {
            throw FirebaseAuthError.invalidPrivateKey
        }

        // Google service account keys use PKCS#8 format.
        // SecKeyCreateWithData expects raw PKCS#1 RSA key data.
        // Strip the PKCS#8 wrapper by parsing the ASN.1 structure.
        keyData = Self.stripPKCS8HeaderIfNeeded(keyData)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw FirebaseAuthError.secKeyCreationFailed(error as Swift.Error)
            }
            throw FirebaseAuthError.invalidPrivateKey
        }

        return secKey
    }

    /// Strips the PKCS#8 PrivateKeyInfo wrapper to extract the raw PKCS#1 RSA key.
    ///
    /// PKCS#8 structure:
    /// ```
    /// SEQUENCE {
    ///   INTEGER (version)
    ///   SEQUENCE { OID rsaEncryption, NULL }
    ///   OCTET STRING { <-- this contains the PKCS#1 key
    ///     SEQUENCE { ... RSA key parameters ... }
    ///   }
    /// }
    /// ```
    private static func stripPKCS8HeaderIfNeeded(_ data: Data) -> Data {
        // Must start with SEQUENCE tag (0x30)
        guard data.count > 26, data[0] == 0x30 else { return data }

        var index = 0

        // Read outer SEQUENCE tag + length (enter the sequence, don't skip it)
        guard readASN1TagAndLength(data, index: &index) != nil else { return data }

        // Skip INTEGER (version = 0)
        guard index < data.count, data[index] == 0x02 else { return data }
        guard skipASN1Element(data, index: &index) else { return data }

        // Skip SEQUENCE (AlgorithmIdentifier: OID rsaEncryption + NULL)
        guard index < data.count, data[index] == 0x30 else { return data }
        guard skipASN1Element(data, index: &index) else { return data }

        // Now at OCTET STRING containing the PKCS#1 RSA key
        guard index < data.count, data[index] == 0x04 else { return data }
        guard let octetLength = readASN1TagAndLength(data, index: &index) else { return data }

        guard index + octetLength <= data.count else { return data }
        return data.subdata(in: index..<(index + octetLength))
    }

    /// Reads an ASN.1 tag and length, advancing `index` past both.
    /// Returns the content length (does NOT skip the content).
    private static func readASN1TagAndLength(_ data: Data, index: inout Int) -> Int? {
        guard index < data.count else { return nil }
        index += 1 // skip tag byte
        return readASN1Length(data, index: &index)
    }

    /// Skips an entire ASN.1 element (tag + length + content).
    private static func skipASN1Element(_ data: Data, index: inout Int) -> Bool {
        guard let length = readASN1TagAndLength(data, index: &index) else { return false }
        index += length
        return index <= data.count
    }

    /// Reads a DER-encoded length, advancing `index` past the length bytes.
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
