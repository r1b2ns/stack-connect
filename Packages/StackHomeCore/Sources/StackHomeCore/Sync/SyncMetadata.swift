import Foundation

/// Per-account record of the last sync attempt. Persisted via `PersistentStorable`
/// under `sync.account.<id>`. Foundation-pure value type shared by iOS and Windows.
public struct SyncMetadata: Codable, Hashable, Sendable {
    public let accountId: String
    public var lastSyncedAt: Date
    public var lastError: String?
    public var appsSynced: Int

    public init(accountId: String, lastSyncedAt: Date, lastError: String? = nil, appsSynced: Int) {
        self.accountId = accountId
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
        self.appsSynced = appsSynced
    }
}
