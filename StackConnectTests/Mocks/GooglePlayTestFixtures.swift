import Foundation
import Security

/// Builders for Google Play service-account key files used across the Play tests.
///
/// Real-looking keys are generated at runtime (`makeRSAPrivateKeyPEM()`) so no
/// private key — not even a throwaway one — is ever committed to the repo.
enum GooglePlayTestFixtures {

    static let clientEmail = "stack-connect@my-project.iam.gserviceaccount.com"
    static let privateKeyId = "0123456789abcdef0123456789abcdef01234567"
    static let projectId = "my-project"

    /// Serialises a key file the way Google does (JSON-escaped PEM). Pass `nil` to
    /// omit a field.
    static func serviceAccountJSON(
        type: String? = "service_account",
        clientEmail: String? = clientEmail,
        privateKeyId: String? = privateKeyId,
        privateKey: String? = "-----BEGIN PRIVATE KEY-----\nMIIEfake\n-----END PRIVATE KEY-----\n",
        projectId: String? = projectId
    ) -> String {
        var object: [String: String] = [:]
        object["type"] = type
        object["client_email"] = clientEmail
        object["private_key_id"] = privateKeyId
        object["private_key"] = privateKey
        object["project_id"] = projectId
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// A fresh RSA-2048 private key as a PKCS#8 PEM (`BEGIN PRIVATE KEY`), the
    /// format Google puts in service-account key files.
    static func makeRSAPrivateKeyPEM() throws -> String {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let pkcs1 = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw error?.takeRetainedValue() ?? FixtureError.keyGenerationFailed
        }
        let pkcs8 = wrapPKCS1InPKCS8(pkcs1)
        let body = pkcs8.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----\n"
    }

    enum FixtureError: Error {
        case keyGenerationFailed
    }

    // MARK: - DER

    /// `PrivateKeyInfo ::= SEQUENCE { version 0, AlgorithmIdentifier rsaEncryption, OCTET STRING pkcs1 }`.
    private static func wrapPKCS1InPKCS8(_ pkcs1: Data) -> Data {
        let version: [UInt8] = [0x02, 0x01, 0x00]
        let rsaAlgorithm: [UInt8] = [
            0x30, 0x0D,
            0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
            0x05, 0x00
        ]
        let octetString: [UInt8] = [0x04] + derLength(pkcs1.count) + [UInt8](pkcs1)
        let content: [UInt8] = version + rsaAlgorithm + octetString
        let sequence: [UInt8] = [0x30] + derLength(content.count) + content
        return Data(sequence)
    }

    private static func derLength(_ length: Int) -> [UInt8] {
        guard length >= 0x80 else { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
