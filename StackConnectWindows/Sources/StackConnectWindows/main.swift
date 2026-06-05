import Foundation
import StackProtocols
import StackCrypto
import StackStorageSQLite
import StackSecretsWindows
import APIProviderFirebase
import APIProviderPlay
import AppStoreConnect_Swift_SDK

// Headless entry point for the Windows app (phase 4 · B1a).
//
// No UI yet. This drives the per-platform bootstrap (B2) and smoke-checks every
// non-UI subsystem so a successful `swift run` on the Windows VM proves the
// whole stack links into one executable — the de-risking step before adding
// SwiftCrossUI in B1b.
//
//   swift run StackConnectWindows

struct StartupError: Error, CustomStringConvertible {
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

print("StackConnect (Windows) — headless bootstrap  (platform: \(platformName()))\n")

// Bootstrap (B2): build the platform environment once and reuse it below.
var environment: AppEnvironment?
await check("Bootstrap: open store + secrets") {
    let env = try Bootstrap.makeEnvironment()
    environment = env
    print("     store: \(env.storePath)")
}

// Persistence: the SQLite-backed PersistentStorable.
await check("Storage round-trip (SQLitePersistentStorable)") {
    guard let storage = environment?.storage else { throw StartupError("no environment") }

    struct Account: Codable, Equatable { let id: String; let name: String }
    let account = Account(id: "smoke", name: "Smoke Test")

    try await storage.save(account, id: account.id)
    guard try await storage.fetch(Account.self, id: "smoke") == account else {
        throw StartupError("fetch mismatch")
    }
    try await storage.delete(Account.self, id: "smoke")
    guard try await storage.fetch(Account.self, id: "smoke") == nil else {
        throw StartupError("delete failed")
    }
}

// Secrets: the Credential Manager-backed KeyStorable.
await check("Secrets round-trip (WindowsCredentialStorable)") {
    guard let secrets = environment?.secrets else { throw StartupError("no environment") }

    let key = "smoke-secret"
    secrets.set("p8-private-key", forKey: key)
    guard secrets.string(forKey: key) == "p8-private-key" else { throw StartupError("read mismatch") }
    secrets.removeObject(forKey: key)
    guard secrets.string(forKey: key) == nil else { throw StartupError("delete failed") }
}

// Crypto: the shared AccountCrypto (swift-crypto) links and round-trips.
await check("Crypto round-trip (AccountCrypto)") {
    let json = #"{"name":"Smoke","providerType":"apple"}"#
    let password = "correct horse battery staple"
    let encrypted = try AccountCrypto.encrypt(json: json, password: password)
    guard try AccountCrypto.decrypt(data: encrypted, password: password) == json else {
        throw StartupError("decrypt mismatch")
    }
}

// Link checks: reference public symbols so the providers and the ASC SDK are
// type-checked and linked into this executable, not stripped.
await check("API providers + ASC SDK link") {
    _ = FirebaseConfiguration.self
    _ = PlayConfiguration.self
    _ = APIConfiguration.self
}

print("")
if failures == 0 {
    print("Bootstrap OK ✅  — non-UI stack links and runs.")
    exit(0)
} else {
    print("Bootstrap failed ❌  — \(failures) check(s) failed.")
    exit(1)
}
