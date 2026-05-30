import Foundation

struct SyncMetadata: Codable, Hashable, Sendable {
    let accountId: String
    var lastSyncedAt: Date
    var lastError: String?
    var appsSynced: Int
}
