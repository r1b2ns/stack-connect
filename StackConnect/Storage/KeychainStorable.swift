import Foundation
import Security

final class KeychainStorable: KeyStorable {

    // MARK: - Singleton

    static let shared = KeychainStorable()

    // MARK: - Properties

    private let service: String

    // MARK: - Init

    init(service: String = Bundle.main.bundleIdentifier ?? "app.stackconnect") {
        self.service = service
    }

    // MARK: - Read (primitives)

    func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func int(forKey key: String) -> Int? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int.self) }
    }

    func double(forKey key: String) -> Double? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Double.self) }
    }

    func bool(forKey key: String) -> Bool? {
        guard let data = data(forKey: key), data.count == 1 else { return nil }
        return data[0] != 0
    }

    func data(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Log.print.error("[Keychain] Read failed for key '\(key)': OSStatus \(status)")
            }
            return nil
        }

        return result as? Data
    }

    // MARK: - Write (primitives)

    func set(_ value: Any?, forKey key: String) {
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
            Log.print.warning("[Keychain] Unsupported value type '\(type(of: value))' for key '\(key)'.")
            return
        }

        guard let encoded else {
            Log.print.error("[Keychain] Encoding failed for key '\(key)'")
            return
        }

        persistData(encoded, forKey: key)
    }

    // MARK: - Remove

    func removeObject(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            Log.print.error("[Keychain] Delete failed for key '\(key)': OSStatus \(status)")
        }
    }

    // MARK: - Private

    private func persistData(_ data: Data, forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status: OSStatus

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        } else {
            var newItem = query
            newItem[kSecValueData]   = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(newItem as CFDictionary, nil)
        }

        if status != errSecSuccess {
            Log.print.error("[Keychain] Write failed for key '\(key)': OSStatus \(status)")
        } else {
            Log.print.info("[Keychain] Saved key '\(key)'")
        }
    }
}
