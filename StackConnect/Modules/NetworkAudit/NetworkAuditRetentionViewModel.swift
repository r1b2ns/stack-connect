import Foundation

// MARK: - Protocol

@MainActor
protocol NetworkAuditRetentionViewModelProtocol: ObservableObject {
    var uiState: NetworkAuditRetentionUiState { get set }
    func load() async
    /// A longer period applies at once; a shorter one asks for confirmation.
    func select(_ retention: NetworkAuditRetention) async
    func confirmReduction() async
    func cancelReduction()
    func setRecordsFullBodies(_ enabled: Bool)
    func deleteAll() async
}

// MARK: - UiState

struct NetworkAuditPendingReduction: Equatable {
    let retention: NetworkAuditRetention
    let cutoff: Date
    let eventCount: Int
}

struct NetworkAuditRetentionUiState {
    var retention: NetworkAuditRetention = .default
    var pendingReduction: NetworkAuditPendingReduction?
    var recordsFullBodies = true
    var stats: NetworkAuditStorageStats = .empty
    var toast: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class NetworkAuditRetentionViewModel: NetworkAuditRetentionViewModelProtocol {

    @Published var uiState = NetworkAuditRetentionUiState()

    private let dependencies: NetworkAuditDependencies

    init(dependencies: NetworkAuditDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func load() async {
        uiState.retention = dependencies.settings.retention
        uiState.recordsFullBodies = dependencies.settings.recordsFullBodies
        uiState.stats = await dependencies.store.stats()
    }

    func select(_ retention: NetworkAuditRetention) async {
        guard retention != uiState.retention else {
            uiState.pendingReduction = nil
            return
        }
        if retention.days > uiState.retention.days {
            uiState.pendingReduction = nil
            apply(retention)
            return
        }
        let cutoff = retention.cutoff(from: dependencies.now())
        let count = await dependencies.store.count(before: cutoff)
        uiState.pendingReduction = NetworkAuditPendingReduction(retention: retention, cutoff: cutoff, eventCount: count)
    }

    func confirmReduction() async {
        guard let pending = uiState.pendingReduction else { return }
        uiState.pendingReduction = nil
        apply(pending.retention)
        let removed = await dependencies.store.purge(before: pending.cutoff)
        uiState.stats = await dependencies.store.stats()
        Log.print.info("[NetworkAudit] Retention reduced to \(pending.retention.days) days, \(removed) events deleted")
    }

    func cancelReduction() {
        uiState.pendingReduction = nil
    }

    func setRecordsFullBodies(_ enabled: Bool) {
        dependencies.settings.recordsFullBodies = enabled
        uiState.recordsFullBodies = enabled
        Log.print.info("[NetworkAudit] Full bodies: \(enabled)")
    }

    func deleteAll() async {
        await dependencies.store.deleteAll()
        dependencies.vault.destroyKey()
        uiState.stats = await dependencies.store.stats()
        uiState.toast = ToastMessage(String(localized: "Log deleted", comment: "Network audit toast: the whole log was deleted."), icon: "trash")
    }

    private func apply(_ retention: NetworkAuditRetention) {
        dependencies.settings.retention = retention
        uiState.retention = retention
        Log.print.info("[NetworkAudit] Retention: \(retention.days) days")
    }
}
