import CryptoKit
import XCTest
@testable import StackConnect

final class AccountCryptoTests: XCTestCase {

    private let samplePayload = #"{"name":"Test","providerType":"apple","credentials":{"key":"value"}}"#
    private let password = "correct horse battery staple"

    func test_encryptDecrypt_roundTrip_returnsOriginalJSON() throws {
        let encrypted = try AccountCrypto.encrypt(json: samplePayload, password: password)
        let decrypted = try AccountCrypto.decrypt(data: encrypted, password: password)
        XCTAssertEqual(decrypted, samplePayload)
    }

    func test_encrypt_writesCurrentVersionByte() throws {
        let encrypted = try AccountCrypto.encrypt(json: samplePayload, password: password)
        XCTAssertEqual(encrypted[4], 0x03, "Encryption must always produce v3 files")
    }

    func test_encrypt_producesUniqueCiphertextEachCall() throws {
        let a = try AccountCrypto.encrypt(json: samplePayload, password: password)
        let b = try AccountCrypto.encrypt(json: samplePayload, password: password)
        XCTAssertNotEqual(a, b, "Random salt + nonce must make every output unique")
    }

    func test_decrypt_withWrongPassword_throwsInvalidPassword() throws {
        let encrypted = try AccountCrypto.encrypt(json: samplePayload, password: password)
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: encrypted, password: "wrong")) { error in
            XCTAssertEqual(error as? AccountCryptoError, .invalidPassword)
        }
    }

    func test_decrypt_withTamperedCiphertext_throwsInvalidPassword() throws {
        var encrypted = try AccountCrypto.encrypt(json: samplePayload, password: password)
        encrypted[encrypted.count - 1] ^= 0xFF
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: encrypted, password: password)) { error in
            XCTAssertEqual(error as? AccountCryptoError, .invalidPassword)
        }
    }

    func test_decrypt_withBadMagic_throwsInvalidFileFormat() {
        let bogus = Data(repeating: 0xAB, count: 100)
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: bogus, password: password)) { error in
            XCTAssertEqual(error as? AccountCryptoError, .invalidFileFormat)
        }
    }

    func test_decrypt_withUnsupportedVersion_throwsUnsupportedVersion() {
        var data = Data("SCEX".utf8)
        data.append(0xFE)
        data.append(Data(repeating: 0, count: 16 + 12 + 16 + 1))
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: data, password: password)) { error in
            XCTAssertEqual(error as? AccountCryptoError, .unsupportedVersion)
        }
    }

    func test_decrypt_truncatedFile_throwsInvalidFileFormat() {
        let tooShort = Data("SCEX".utf8) + Data([0x02]) + Data(repeating: 0, count: 10)
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: tooShort, password: password)) { error in
            XCTAssertEqual(error as? AccountCryptoError, .invalidFileFormat)
        }
    }

    /// Generates a v1 file using the legacy HKDF algorithm and verifies the current
    /// implementation can still decrypt it. Protects users who have older `.scexport` files.
    func test_decrypt_legacyV1File_succeeds() throws {
        let v1File = try makeV1File(json: samplePayload, password: password)
        XCTAssertEqual(v1File[4], 0x01)

        let decrypted = try AccountCrypto.decrypt(data: v1File, password: password)
        XCTAssertEqual(decrypted, samplePayload)
    }

    func test_decrypt_legacyV1File_wrongPassword_throwsInvalidPassword() throws {
        let v1File = try makeV1File(json: samplePayload, password: password)
        XCTAssertThrowsError(try AccountCrypto.decrypt(data: v1File, password: "nope")) { error in
            XCTAssertEqual(error as? AccountCryptoError, .invalidPassword)
        }
    }

    // MARK: - V1 fixture builder

    private func makeV1File(json: String, password: String) throws -> Data {
        // Mirror the legacy algorithm bit-for-bit. Must stay in sync with deriveKeyV1.
        let appSalt = Data([
            0x4A, 0xC7, 0x1E, 0x93, 0xD2, 0x58, 0xBF, 0x06,
            0x7D, 0xA4, 0x3B, 0xE1, 0x90, 0xF5, 0x2C, 0x68,
            0x15, 0x87, 0xDA, 0x4F, 0xC3, 0x72, 0xAE, 0x09,
            0x5B, 0xE6, 0x31, 0x8C, 0xF0, 0x64, 0xA9, 0x2D
        ])
        let info = Data("StackConnect.Export.v1".utf8)

        let randomSalt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })

        var inputMaterial = appSalt
        inputMaterial.append(Data(password.utf8))
        let inputKey = SymmetricKey(data: SHA256.hash(data: inputMaterial))
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: randomSalt,
            info: info,
            outputByteCount: 32
        )

        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(Data(json.utf8), using: key, nonce: nonce)

        var output = Data("SCEX".utf8)
        output.append(0x01)
        output.append(randomSalt)
        output.append(contentsOf: nonce)
        output.append(sealed.ciphertext)
        output.append(sealed.tag)
        return output
    }
}
