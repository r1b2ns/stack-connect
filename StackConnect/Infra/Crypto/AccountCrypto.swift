import CryptoKit
import Foundation

enum AccountCryptoError: LocalizedError {
    case encryptionFailed
    case invalidFileFormat
    case unsupportedVersion
    case decryptionFailed
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:  return String(localized: "Failed to encrypt data.")
        case .invalidFileFormat: return String(localized: "Invalid file format. This is not a StackConnect export file.")
        case .unsupportedVersion: return String(localized: "Unsupported file version.")
        case .decryptionFailed:  return String(localized: "Failed to decrypt file.")
        case .invalidPassword:   return String(localized: "Invalid password or corrupted file.")
        }
    }
}

/// AES-256-GCM encryption for account export files.
///
/// File format (.scexport):
/// ```
/// [4 bytes]  Magic: "SCEX"
/// [1 byte]   Version: 0x01
/// [16 bytes] Random salt
/// [12 bytes] Nonce
/// [N bytes]  Ciphertext + GCM tag (16 bytes)
/// ```
struct AccountCrypto {

    // MARK: - Constants

    /// Fixed app-level salt (32 bytes). Combined with user password to derive encryption key.
    /// This ensures files are only decryptable by StackConnect.
    private static let appSalt = Data([
        0x4A, 0xC7, 0x1E, 0x93, 0xD2, 0x58, 0xBF, 0x06,
        0x7D, 0xA4, 0x3B, 0xE1, 0x90, 0xF5, 0x2C, 0x68,
        0x15, 0x87, 0xDA, 0x4F, 0xC3, 0x72, 0xAE, 0x09,
        0x5B, 0xE6, 0x31, 0x8C, 0xF0, 0x64, 0xA9, 0x2D
    ])

    private static let magic = Data("SCEX".utf8)
    private static let version: UInt8 = 1
    private static let info = Data("StackConnect.Export.v1".utf8)

    private static let saltLength = 16
    private static let nonceLength = 12

    // MARK: - Public

    /// Encrypts a JSON string with the given password.
    /// Returns binary data in `.scexport` format.
    static func encrypt(json: String, password: String) throws -> Data {
        guard let jsonData = json.data(using: .utf8) else {
            throw AccountCryptoError.encryptionFailed
        }

        // Generate random salt and nonce
        var randomSalt = Data(count: saltLength)
        _ = randomSalt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }

        let symmetricKey = deriveKey(password: password, salt: randomSalt)

        var nonceData = Data(count: nonceLength)
        _ = nonceData.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, nonceLength, $0.baseAddress!) }
        let nonce = try AES.GCM.Nonce(data: nonceData)

        let sealedBox = try AES.GCM.seal(jsonData, using: symmetricKey, nonce: nonce)

        // Build file: magic + version + salt + nonce + ciphertext+tag
        var output = Data()
        output.append(magic)
        output.append(version)
        output.append(randomSalt)
        output.append(contentsOf: nonce)
        output.append(sealedBox.ciphertext)
        output.append(sealedBox.tag)

        return output
    }

    /// Decrypts binary `.scexport` data with the given password.
    /// Returns the original JSON string.
    static func decrypt(data: Data, password: String) throws -> String {
        // Validate minimum size: magic(4) + version(1) + salt(16) + nonce(12) + tag(16) = 49
        guard data.count >= 49 else {
            throw AccountCryptoError.invalidFileFormat
        }

        var offset = 0

        // Validate magic
        let fileMagic = data[offset..<offset + 4]
        guard fileMagic == magic else {
            throw AccountCryptoError.invalidFileFormat
        }
        offset += 4

        // Validate version
        let fileVersion = data[offset]
        guard fileVersion == version else {
            throw AccountCryptoError.unsupportedVersion
        }
        offset += 1

        // Read salt
        let salt = data[offset..<offset + saltLength]
        offset += saltLength

        // Read nonce
        let nonceData = data[offset..<offset + nonceLength]
        offset += nonceLength

        // Read ciphertext + tag
        let remaining = data[offset...]
        guard remaining.count >= 16 else {
            throw AccountCryptoError.invalidFileFormat
        }

        let ciphertextAndTag = remaining

        // Derive key
        let symmetricKey = deriveKey(password: password, salt: Data(salt))

        // Decrypt
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertextAndTag.dropLast(16),
                tag: ciphertextAndTag.suffix(16)
            )

            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

            guard let json = String(data: decryptedData, encoding: .utf8) else {
                throw AccountCryptoError.decryptionFailed
            }

            return json
        } catch is AccountCryptoError {
            throw AccountCryptoError.invalidPassword
        } catch {
            throw AccountCryptoError.invalidPassword
        }
    }

    // MARK: - Private

    /// Derives a 256-bit symmetric key from password + app salt + random salt using HKDF.
    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        // Combine app salt + password
        var inputMaterial = appSalt
        inputMaterial.append(Data(password.utf8))

        // Hash to get consistent-length input key material
        let hashedInput = SHA256.hash(data: inputMaterial)
        let inputKey = SymmetricKey(data: hashedInput)

        // Derive final key using HKDF
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return derivedKey
    }
}
