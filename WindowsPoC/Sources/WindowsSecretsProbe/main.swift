import Foundation

// Probes the Windows Credential Manager (the intended backing store for secrets
// on Windows, replacing the iOS Keychain). Isolated in its own executable so the
// platform-specific Win32 code never blocks the core PoC build.
//
//   swift run WindowsSecretsProbe
//
// NOTE: the Win32 path has only been validated by compilation reasoning, not run
// on Windows yet — this probe is exactly how you confirm it.

struct ProbeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

#if os(Windows)
import WinSDK

private func wide(_ string: String) -> [UInt16] {
    Array(string.utf16) + [0]
}

private func writeSecret(target: String, secret: String) throws {
    var targetW = wide(target)
    var blob = Array(secret.utf8)

    try targetW.withUnsafeMutableBufferPointer { targetPtr in
        try blob.withUnsafeMutableBufferPointer { blobPtr in
            var credential = CREDENTIALW()
            credential.Type = DWORD(CRED_TYPE_GENERIC)
            credential.TargetName = targetPtr.baseAddress
            credential.CredentialBlobSize = DWORD(blobPtr.count)
            credential.CredentialBlob = blobPtr.baseAddress
            credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)

            if !CredWriteW(&credential, 0).boolValue {
                throw ProbeError("CredWriteW failed (GetLastError=\(GetLastError()))")
            }
        }
    }
}

private func readSecret(target: String) throws -> String {
    var pointer: PCREDENTIALW?
    let ok = wide(target).withUnsafeBufferPointer {
        CredReadW($0.baseAddress, DWORD(CRED_TYPE_GENERIC), 0, &pointer).boolValue
    }
    guard ok, let credential = pointer?.pointee else {
        throw ProbeError("CredReadW failed (GetLastError=\(GetLastError()))")
    }
    defer { CredFree(pointer) }

    let data = Data(bytes: credential.CredentialBlob, count: Int(credential.CredentialBlobSize))
    return String(decoding: data, as: UTF8.self)
}

private func deleteSecret(target: String) {
    _ = wide(target).withUnsafeBufferPointer {
        CredDeleteW($0.baseAddress, DWORD(CRED_TYPE_GENERIC), 0)
    }
}

func runProbe() throws {
    let target = "StackConnect.PoC.secret"
    let secret = "p8-private-key-\(UUID().uuidString)"

    try writeSecret(target: target, secret: secret)
    defer { deleteSecret(target: target) }

    let readBack = try readSecret(target: target)
    guard readBack == secret else {
        throw ProbeError("read value did not match written value")
    }
}

#else

func runProbe() throws {
    throw ProbeError("Windows Credential Manager probe only runs on Windows")
}

#endif

print("Windows Credential Manager probe\n")
do {
    try runProbe()
    print("  ✅ write / read / delete round-trip")
    print("\nProbe passed ✅")
    exit(0)
} catch {
    #if os(Windows)
    print("  ❌ \(error)")
    print("\nProbe failed ❌")
    exit(1)
    #else
    print("  ⏭️  \(error)")
    exit(0)
    #endif
}
