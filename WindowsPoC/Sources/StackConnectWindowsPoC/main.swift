import Foundation
import Crypto
import _CryptoExtras
import StackProtocols
import StackCrypto
import StackStorageSQLite
import APIProviderFirebase
import APIProviderPlay

// MARK: - Tiny harness

struct PoCError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

func platformName() -> String {
    #if os(Windows)
    return "Windows"
    #elseif os(macOS)
    return "macOS"
    #elseif os(Linux)
    return "Linux"
    #else
    return "unknown"
    #endif
}

var failures = 0

@MainActor
func check(_ name: String, _ body: () async throws -> Void) async {
    do {
        try await body()
        print("  ✅ \(name)")
    } catch {
        failures += 1
        print("  ❌ \(name): \(error)")
    }
}

func skip(_ name: String, _ reason: String) {
    print("  ⏭️  \(name) — \(reason)")
}

// MARK: - Checks

print("StackConnect — shared logic PoC  (platform: \(platformName()))\n")

// 1. Persistence: the cross-platform SQLite backend.
await check("SQLite CRUD round-trip (SQLitePersistentStorable)") {
    struct Item: Codable, Equatable { let id: String; let value: Int }

    let path = NSTemporaryDirectory() + "stackconnect-poc-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let store = try SQLitePersistentStorable(path: path)
    let item = Item(id: "1", value: 42)
    try await store.save(item, id: item.id)
    guard try await store.fetch(Item.self, id: "1") == item else { throw PoCError("fetch mismatch") }

    try await store.save(Item(id: "1", value: 99), id: "1")
    guard try await store.fetch(Item.self, id: "1")?.value == 99 else { throw PoCError("overwrite failed") }
    guard try await store.fetchAll(Item.self).count == 1 else { throw PoCError("fetchAll count != 1") }

    try await store.delete(Item.self, id: "1")
    guard try await store.fetch(Item.self, id: "1") == nil else { throw PoCError("delete failed") }
}

// 2. Export crypto: AES-GCM seal/open with PBKDF2 key derivation.
await check("AccountCrypto AES-GCM + PBKDF2 round-trip (StackCrypto)") {
    let password = AccountCrypto.generateStrongPassword()
    let json = #"{"accounts":[{"id":"a1","name":"Acme"}]}"#

    let encrypted = try AccountCrypto.encrypt(json: json, password: password)
    let decrypted = try AccountCrypto.decrypt(data: encrypted, password: password)
    guard decrypted == json else { throw PoCError("round-trip mismatch") }

    do {
        _ = try AccountCrypto.decrypt(data: encrypted, password: "wrong-password")
        throw PoCError("wrong password was accepted")
    } catch let error as AccountCryptoError where error == .invalidPassword {
        // expected
    }
}

// 3. JWT signing primitive: RS256 (RSASSA-PKCS1-v1_5 over SHA-256) used by the
//    Firebase / Google Play providers.
await check("RS256 sign + verify (_RSA.Signing)") {
    let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
    let message = Data("header.payload".utf8)

    let signature = try key.signature(for: message, padding: .insecurePKCS1v1_5)
    guard key.publicKey.isValidSignature(signature, for: message, padding: .insecurePKCS1v1_5) else {
        throw PoCError("valid signature rejected")
    }

    var tampered = message
    tampered.append(0x21)
    guard !key.publicKey.isValidSignature(signature, for: tampered, padding: .insecurePKCS1v1_5) else {
        throw PoCError("tampered message accepted")
    }
}

// 4. PEM parsing: the path Firebase/PlayConfiguration uses to load the service
//    account private key.
await check("RSA PEM round-trip (_RSA.Signing.PrivateKey pemRepresentation)") {
    let original = try _RSA.Signing.PrivateKey(keySize: .bits2048)
    let pem = original.pemRepresentation
    let reparsed = try _RSA.Signing.PrivateKey(pemRepresentation: pem)

    let message = Data("pem-check".utf8)
    let signature = try reparsed.signature(for: message, padding: .insecurePKCS1v1_5)
    guard original.publicKey.isValidSignature(signature, for: message, padding: .insecurePKCS1v1_5) else {
        throw PoCError("reparsed key produced a non-matching signature")
    }
}

// 5. Optional: build the real provider configurations from service-account files,
//    exercising PEM parsing on real credentials. Set the env vars to enable.
let env = ProcessInfo.processInfo.environment

if let path = env["FIREBASE_SA_JSON"] {
    await check("FirebaseConfiguration from \(path)") {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        _ = try FirebaseConfiguration(serviceAccountJSON: data)
    }
} else {
    skip("FirebaseConfiguration", "set FIREBASE_SA_JSON to a service-account .json to test")
}

if let path = env["PLAY_SA_JSON"] {
    await check("PlayConfiguration from \(path)") {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        _ = try PlayConfiguration(serviceAccountJSON: data)
    }
} else {
    skip("PlayConfiguration", "set PLAY_SA_JSON to a service-account .json to test")
}

// MARK: - Result

print("")
if failures == 0 {
    print("All checks passed ✅")
    exit(0)
} else {
    print("\(failures) check(s) failed ❌")
    exit(1)
}
