import CommonCrypto
import CryptoKit
import Foundation

enum AccountCryptoError: LocalizedError {
    case encryptionFailed
    case invalidFileFormat
    case unsupportedVersion
    case decryptionFailed
    case invalidPassword
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:    return String(localized: "Failed to encrypt data.")
        case .invalidFileFormat:   return String(localized: "Invalid file format. This is not a StackConnect export file.")
        case .unsupportedVersion:  return String(localized: "Unsupported file version.")
        case .decryptionFailed:    return String(localized: "Failed to decrypt file.")
        case .invalidPassword:     return String(localized: "Invalid password or corrupted file.")
        case .keyDerivationFailed: return String(localized: "Failed to derive encryption key.")
        }
    }
}

/// AES-256-GCM encryption for account export files.
///
/// File format (.scexport):
/// ```
/// [4 bytes]  Magic: "SCEX"
/// [1 byte]   Version
/// [4 bytes]  PBKDF2 iterations (UInt32 big-endian) — v3 only
/// [16 bytes] Random salt
/// [12 bytes] Nonce
/// [N bytes]  Ciphertext + GCM tag (16 bytes)
/// ```
///
/// Versions:
/// - v1 (legacy): key = HKDF(SHA256(appSalt || password), randomSalt). Fast — vulnerable to offline brute-force.
///   Decryption only — kept for migrating older `.scexport` files.
/// - v2 (legacy): key = PBKDF2-SHA256(password, appSalt || randomSalt, 600_000, 32). Iterations implied by the constant.
///   Decryption only.
/// - v3 (current): same KDF as v2 but the iteration count is stored in the header, so changing the default
///   later does not break older files.
struct AccountCrypto {

    // MARK: - Constants

    /// Fixed app-level salt (32 bytes). Mixed with the per-file random salt so that decryption
    /// requires both the user password AND the StackConnect binary. Not a secret — present in
    /// every shipped IPA — but binds the file format to this app.
    private static let appSalt = Data([
        0x4A, 0xC7, 0x1E, 0x93, 0xD2, 0x58, 0xBF, 0x06,
        0x7D, 0xA4, 0x3B, 0xE1, 0x90, 0xF5, 0x2C, 0x68,
        0x15, 0x87, 0xDA, 0x4F, 0xC3, 0x72, 0xAE, 0x09,
        0x5B, 0xE6, 0x31, 0x8C, 0xF0, 0x64, 0xA9, 0x2D
    ])

    private static let magic = Data("SCEX".utf8)
    private static let currentVersion: UInt8 = 0x03
    private static let legacyHKDFInfo = Data("StackConnect.Export.v1".utf8)
    private static let pbkdf2Iterations: UInt32 = 600_000

    private static let saltLength = 16
    private static let nonceLength = 12
    private static let tagLength = 16

    // MARK: - Public

    /// Encrypts a JSON string with the given password. Always writes the current format version.
    static func encrypt(json: String, password: String) throws -> Data {
        guard let jsonData = json.data(using: .utf8) else {
            throw AccountCryptoError.encryptionFailed
        }

        let randomSalt = try randomBytes(count: saltLength)
        let nonceData = try randomBytes(count: nonceLength)
        let iterations = pbkdf2Iterations

        let symmetricKey = try deriveKeyPBKDF2(password: password, randomSalt: randomSalt, iterations: iterations)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.seal(jsonData, using: symmetricKey, nonce: nonce)

        var output = Data()
        output.append(magic)
        output.append(currentVersion)
        output.append(uint32BE(iterations))
        output.append(randomSalt)
        output.append(contentsOf: nonce)
        output.append(sealedBox.ciphertext)
        output.append(sealedBox.tag)
        return output
    }

    /// Decrypts binary `.scexport` data with the given password. Supports v1, v2, and v3.
    static func decrypt(data: Data, password: String) throws -> String {
        guard data.count >= 5 else { throw AccountCryptoError.invalidFileFormat }

        var offset = 0

        let fileMagic = data[offset..<offset + 4]
        guard fileMagic == magic else { throw AccountCryptoError.invalidFileFormat }
        offset += 4

        let fileVersion = data[offset]
        offset += 1

        var iterations = pbkdf2Iterations
        if fileVersion == 0x03 {
            guard data.count >= offset + 4 else { throw AccountCryptoError.invalidFileFormat }
            iterations = readUInt32BE(data, at: offset)
            offset += 4
        }

        guard data.count >= offset + saltLength + nonceLength + tagLength else {
            throw AccountCryptoError.invalidFileFormat
        }

        let salt = Data(data[offset..<offset + saltLength])
        offset += saltLength

        let nonceData = data[offset..<offset + nonceLength]
        offset += nonceLength

        let ciphertextAndTag = data[offset...]
        guard ciphertextAndTag.count >= tagLength else { throw AccountCryptoError.invalidFileFormat }

        let symmetricKey: SymmetricKey
        switch fileVersion {
        case 0x01: symmetricKey = deriveKeyV1(password: password, randomSalt: salt)
        case 0x02: symmetricKey = try deriveKeyPBKDF2(password: password, randomSalt: salt, iterations: pbkdf2Iterations)
        case 0x03: symmetricKey = try deriveKeyPBKDF2(password: password, randomSalt: salt, iterations: iterations)
        default:   throw AccountCryptoError.unsupportedVersion
        }

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertextAndTag.dropLast(tagLength),
                tag: ciphertextAndTag.suffix(tagLength)
            )
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            guard let json = String(data: decryptedData, encoding: .utf8) else {
                throw AccountCryptoError.decryptionFailed
            }
#if DEBUG
            // Debug-only: when the flag is ON, dump the full decrypted payload to the console.
            // Uses `print` (not `Log.print`/os.Logger, which truncates/redacts) so the whole
            // payload is visible — same precedent as `RustCoreDebugLogger`. Wrapped in `#if DEBUG`
            // in addition to the flag check because the payload contains credentials
            // (issuerID / privateKeyID / the `.p8` private key / serviceAccountJSON): secrets
            // must never be printable in a release build even if the flag is somehow enabled.
            if FeatureFlags.shared.isEnabled(.useRustCoreDebugLogging) {
                print("[AccountCrypto] Decrypted .scexport payload:\n\(json)")
            }
#endif
            return json
        } catch {
            throw AccountCryptoError.invalidPassword
        }
    }

    /// Generates a high-entropy random password from an unambiguous alphabet.
    /// 24 chars over a 68-symbol set ≈ 146 bits of entropy. `SystemRandomNumberGenerator`
    /// is cryptographically secure on Apple platforms.
    static func generateStrongPassword(length: Int = 24) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    // MARK: - Private

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard result == errSecSuccess else { throw AccountCryptoError.encryptionFailed }
        return data
    }

    private static func uint32BE(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return data[start..<start + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// PBKDF2-SHA256 with the given iteration count. Salt = appSalt || randomSalt.
    private static func deriveKeyPBKDF2(password: String, randomSalt: Data, iterations: UInt32) throws -> SymmetricKey {
        var combinedSalt = appSalt
        combinedSalt.append(randomSalt)

        var derived = Data(count: 32)
        let passwordBytes = Array(password.utf8)

        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            combinedSalt.withUnsafeBytes { saltBytes -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes, passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, combinedSalt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        guard status == kCCSuccess else { throw AccountCryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    /// v1 (legacy): SHA256(appSalt || password) → HKDF<SHA256>. Decryption only.
    private static func deriveKeyV1(password: String, randomSalt: Data) -> SymmetricKey {
        var inputMaterial = appSalt
        inputMaterial.append(Data(password.utf8))
        let hashedInput = SHA256.hash(data: inputMaterial)
        let inputKey = SymmetricKey(data: hashedInput)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: randomSalt,
            info: legacyHKDFInfo,
            outputByteCount: 32
        )
    }
}
