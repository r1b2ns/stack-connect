import Foundation
import Security
@testable import StackConnect

/// In-memory `KeychainBackend` modelling the lock states that matter:
/// while `isLocked`, items (and adds) of class `WhenUnlocked` answer
/// `errSecInteractionNotAllowed`, `AfterFirstUnlock` ones keep working (the
/// device was unlocked once since boot). Statuses can also be forced.
final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {

    struct Item: Equatable {
        var data: Data
        var accessibility: String
    }

    enum Call: Equatable {
        case copyMatching(key: String?)
        case add(key: String)
        case update(key: String, setsData: Bool, accessibility: String?)
        case delete(key: String)
    }

    private let lock = NSLock()
    private var _items: [String: Item] = [:]
    private var _calls: [Call] = []

    /// Device locked after its first unlock.
    var isLocked = false
    /// Forces the answer of every `update` (e.g. the migration's).
    var forcedUpdateStatus: OSStatus?
    /// Forces the answer of the `update` of these keys only.
    var forcedUpdateStatusByKey: [String: OSStatus] = [:]
    /// Forces the answer of a listing (`kSecMatchLimitAll`).
    var forcedListStatus: OSStatus?

    var items: [String: Item] {
        get { lock.withLock { _items } }
        set { lock.withLock { _items = newValue } }
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func resetCalls() {
        lock.withLock { _calls = [] }
    }

    private static let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    private func isReachable(_ item: Item) -> Bool {
        !isLocked || item.accessibility != Self.whenUnlocked
    }

    private func key(of query: [String: Any]) -> String? {
        query[kSecAttrAccount as String] as? String
    }

    // MARK: - KeychainBackend

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        lock.withLock {
            let key = key(of: query)
            _calls.append(.copyMatching(key: key))

            if (query[kSecMatchLimit as String] as? String) == (kSecMatchLimitAll as String) {
                if let forcedListStatus { return (forcedListStatus, nil) }
                if isLocked && _items.values.contains(where: { !isReachable($0) }) {
                    return (errSecInteractionNotAllowed, nil)
                }
                guard !_items.isEmpty else { return (errSecItemNotFound, nil) }
                let list: [[String: Any]] = _items.map { key, item in
                    [kSecAttrAccount as String: key, kSecAttrAccessible as String: item.accessibility]
                }
                return (errSecSuccess, list as NSArray)
            }

            guard let key, let item = _items[key] else { return (errSecItemNotFound, nil) }
            guard isReachable(item) else { return (errSecInteractionNotAllowed, nil) }
            let returnsData = query[kSecReturnData as String] as? Bool ?? false
            return (errSecSuccess, returnsData ? item.data as NSData : nil)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard let key = key(of: attributes),
                  let data = attributes[kSecValueData as String] as? Data,
                  let accessibility = attributes[kSecAttrAccessible as String] as? String else {
                return errSecParam
            }
            _calls.append(.add(key: key))
            guard _items[key] == nil else { return errSecDuplicateItem }
            let item = Item(data: data, accessibility: accessibility)
            guard isReachable(item) else { return errSecInteractionNotAllowed }
            _items[key] = item
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard let key = key(of: query) else { return errSecParam }
            let data = attributes[kSecValueData as String] as? Data
            let accessibility = attributes[kSecAttrAccessible as String] as? String
            _calls.append(.update(key: key, setsData: data != nil, accessibility: accessibility))

            if let forced = forcedUpdateStatusByKey[key] ?? forcedUpdateStatus { return forced }
            guard var item = _items[key] else { return errSecItemNotFound }
            guard isReachable(item) else { return errSecInteractionNotAllowed }
            if let data { item.data = data }
            if let accessibility { item.accessibility = accessibility }
            _items[key] = item
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            guard let key = key(of: query) else { return errSecParam }
            _calls.append(.delete(key: key))
            guard let item = _items[key] else { return errSecItemNotFound }
            guard isReachable(item) else { return errSecInteractionNotAllowed }
            _items[key] = nil
            return errSecSuccess
        }
    }
}
