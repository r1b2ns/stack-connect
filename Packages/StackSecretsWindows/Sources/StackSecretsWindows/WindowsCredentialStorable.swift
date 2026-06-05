import Foundation
import StackProtocols

#if os(Windows)
import WinSDK
#endif

/// `KeyStorable` backed by the Windows Credential Manager — the Windows
/// counterpart to the iOS Keychain (`KeychainStorable`). Each value is stored as
/// a generic credential whose `TargetName` is `"<service>:<key>"`.
///
/// The primitive encoding mirrors `KeychainStorable` byte-for-byte
/// (String → UTF-8, Int/Double → raw little-endian bytes, Bool → one byte,
/// Data → raw) so the two backends are interchangeable. `object`/`setObject`
/// are provided by the `KeyStorable` default extension in `StackProtocols`.
///
/// On non-Windows platforms the credential store is replaced by an in-memory
/// dictionary. That path exists only so this package builds and unit-tests on
/// the macOS host — it never ships in the iOS app (iOS uses `KeychainStorable`),
/// and the package is intentionally kept out of `project.yml`.
public final class WindowsCredentialStorable: KeyStorable {

    private let service: String

    #if !os(Windows)
    // Host-only fallback store. Guarded by a lock so concurrent access from
    // tests stays race-free.
    private let lock = NSLock()
    private var memory: [String: Data] = [:]
    #endif

    public init(service: String = "app.stackconnect") {
        self.service = service
    }

    private func target(for key: String) -> String {
        "\(service):\(key)"
    }

    // MARK: - Read (primitives)

    public func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func int(forKey key: String) -> Int? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }

    public func double(forKey key: String) -> Double? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }

    public func bool(forKey key: String) -> Bool? {
        guard let data = data(forKey: key), data.count == 1 else { return nil }
        return data[data.startIndex] != 0
    }

    public func data(forKey key: String) -> Data? {
        rawRead(target: target(for: key))
    }

    // MARK: - Write (primitives)

    public func set(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }

        let encoded: Data?

        switch value {
        case let s as String:
            encoded = s.data(using: .utf8)
        case let i as Int:
            encoded = withUnsafeBytes(of: i) { Data($0) }
        case let d as Double:
            encoded = withUnsafeBytes(of: d) { Data($0) }
        case let b as Bool:
            encoded = Data([b ? 1 : 0])
        case let d as Data:
            encoded = d
        default:
            return
        }

        guard let encoded else { return }
        rawWrite(encoded, target: target(for: key))
    }

    // MARK: - Remove

    public func removeObject(forKey key: String) {
        rawDelete(target: target(for: key))
    }
}

// MARK: - Credential store backend (Windows)

#if os(Windows)
private extension WindowsCredentialStorable {

    func wide(_ string: String) -> [UInt16] {
        Array(string.utf16) + [0]
    }

    func rawWrite(_ data: Data, target: String) {
        var targetW = wide(target)
        var blob = [UInt8](data)

        targetW.withUnsafeMutableBufferPointer { targetPtr in
            blob.withUnsafeMutableBufferPointer { blobPtr in
                var credential = CREDENTIALW()
                credential.Type = DWORD(CRED_TYPE_GENERIC)
                credential.TargetName = targetPtr.baseAddress
                credential.CredentialBlobSize = DWORD(blobPtr.count)
                credential.CredentialBlob = blobPtr.baseAddress
                credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                _ = CredWriteW(&credential, 0)
            }
        }
    }

    func rawRead(target: String) -> Data? {
        var pointer: PCREDENTIALW?
        let ok = wide(target).withUnsafeBufferPointer {
            CredReadW($0.baseAddress, DWORD(CRED_TYPE_GENERIC), 0, &pointer)
        }
        guard ok, let credential = pointer?.pointee else { return nil }
        defer { CredFree(pointer) }

        guard let blob = credential.CredentialBlob, credential.CredentialBlobSize > 0 else {
            return Data()
        }
        return Data(bytes: blob, count: Int(credential.CredentialBlobSize))
    }

    func rawDelete(target: String) {
        _ = wide(target).withUnsafeBufferPointer {
            CredDeleteW($0.baseAddress, DWORD(CRED_TYPE_GENERIC), 0)
        }
    }
}

// MARK: - Credential store backend (host fallback, non-Windows)

#else
private extension WindowsCredentialStorable {

    func rawWrite(_ data: Data, target: String) {
        lock.lock(); defer { lock.unlock() }
        memory[target] = data
    }

    func rawRead(target: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return memory[target]
    }

    func rawDelete(target: String) {
        lock.lock(); defer { lock.unlock() }
        memory.removeValue(forKey: target)
    }
}
#endif
