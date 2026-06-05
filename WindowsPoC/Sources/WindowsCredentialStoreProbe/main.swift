import Foundation
import StackProtocols
import StackSecretsWindows

// Exercises the A2 deliverable — `WindowsCredentialStorable` — through the
// `KeyStorable` protocol, so the gate proves the *typed* implementation builds
// and round-trips on Windows (the raw Win32 calls themselves are also covered by
// the sibling WindowsSecretsProbe). On Windows this hits the real Credential
// Manager; on the host it hits the in-memory fallback.
//
//   swift run WindowsCredentialStoreProbe

struct ProbeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

func expect(_ condition: Bool, _ what: String) throws {
    if !condition { throw ProbeError("expectation failed: \(what)") }
}

func runProbe() throws {
    // Use the protocol type to prove the witness table is wired correctly.
    let store: KeyStorable = WindowsCredentialStorable(service: "StackConnect.PoC.credstore")

    let suffix = UUID().uuidString
    let kString = "string-\(suffix)"
    let kInt = "int-\(suffix)"
    let kDouble = "double-\(suffix)"
    let kBool = "bool-\(suffix)"
    let kData = "data-\(suffix)"
    let kObject = "object-\(suffix)"

    defer {
        for key in [kString, kInt, kDouble, kBool, kData, kObject] {
            store.removeObject(forKey: key)
        }
    }

    // Primitives
    store.set("p8-private-key", forKey: kString)
    try expect(store.string(forKey: kString) == "p8-private-key", "string round-trip")

    store.set(600_000, forKey: kInt)
    try expect(store.int(forKey: kInt) == 600_000, "int round-trip")

    store.set(3.14159, forKey: kDouble)
    try expect(store.double(forKey: kDouble) == 3.14159, "double round-trip")

    store.set(true, forKey: kBool)
    try expect(store.bool(forKey: kBool) == true, "bool round-trip")

    let blob = Data([0x00, 0x01, 0xFF, 0x7F, 0x80])
    store.set(blob, forKey: kData)
    try expect(store.data(forKey: kData) == blob, "data round-trip")

    // Codable object (default extension)
    struct Credentials: Codable, Equatable {
        let keyID: String
        let issuerID: String
    }
    let value = Credentials(keyID: "ABC123", issuerID: "issuer-1")
    store.setObject(value, forKey: kObject)
    let read: Credentials? = store.object(forKey: kObject)
    try expect(read == value, "codable object round-trip")

    // Remove
    store.removeObject(forKey: kString)
    try expect(store.string(forKey: kString) == nil, "remove deletes the value")

    // set(nil) removes
    store.set("temp", forKey: kInt)
    store.set(nil, forKey: kInt)
    try expect(store.int(forKey: kInt) == nil, "set(nil) deletes the value")
}

print("WindowsCredentialStorable probe (KeyStorable contract)\n")
do {
    try runProbe()
    print("  ✅ string / int / double / bool / data / object / remove round-trip")
    print("\nProbe passed ✅")
    exit(0)
} catch {
    print("  ❌ \(error)")
    print("\nProbe failed ❌")
    exit(1)
}
