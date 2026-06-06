import Foundation

// MARK: - State

/// Observable snapshot of the sync pipeline, surfaced to the Home UI.
///
/// Foundation-pure value type shared by iOS and Windows. The `SyncService`
/// orchestrator that mutates it (and its Apple-only side effects) is migrated
/// separately in T-A9.
public struct SyncState: Equatable, Sendable {
    public var isSyncing: Bool
    public var accountsInProgress: Set<String>
    public var lastSyncedAt: Date?
    public var lastError: String?

    public init(
        isSyncing: Bool = false,
        accountsInProgress: Set<String> = [],
        lastSyncedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.isSyncing = isSyncing
        self.accountsInProgress = accountsInProgress
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
    }
}

// MARK: - Mode

public enum SyncMode: Sendable {
    /// Apps, enrichment, reviews, phased. Used at foreground launch + pull-to-refresh.
    case full
    /// Apps + enrichment + phased only — skips reviews to fit in BG refresh budgets.
    case lightweight
}
