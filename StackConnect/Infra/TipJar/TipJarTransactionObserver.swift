import Foundation
import StoreKit

/// Finishes tip transactions that complete outside the tip jar screen: Ask to
/// Buy approvals, purchases interrupted by an app kill, and anything left
/// unfinished by an earlier launch.
///
/// Created once at launch (`StackConnectApp`) and kept for the app's lifetime.
/// A single long-lived task listens to `Transaction.updates` and drains
/// `Transaction.unfinished`; it is cancelled when the observer is released.
final class TipJarTransactionObserver: Sendable {

    /// Called after a verified tip transaction is finished.
    typealias TipCompletionHandler = @Sendable () async -> Void

    private let task: Task<Void, Never>

    /// - Parameter onTipCompleted: Runs after each verified tip transaction is
    ///   finished (e.g. an Ask to Buy approval). By default it records the tip
    ///   so the Home "support the project" card never shows again.
    init(
        tipProductIDs: Set<String> = Set(TipJarCatalog.productIDs),
        onTipCompleted: @escaping TipCompletionHandler = { await TipJarPromptService.shared.recordCompletedTip() }
    ) {
        task = Task(priority: .background) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await result in Transaction.updates {
                        await Self.handle(result, tipProductIDs: tipProductIDs, onTipCompleted: onTipCompleted)
                    }
                }
                group.addTask {
                    for await result in Transaction.unfinished {
                        await Self.handle(result, tipProductIDs: tipProductIDs, onTipCompleted: onTipCompleted)
                    }
                }
            }
        }
        Log.print.info("[TipJar] Transaction observer started")
    }

    deinit {
        task.cancel()
    }

    /// Only verified transactions of a tip product are finished. Unverified
    /// ones stay unfinished so StoreKit delivers them again; other products
    /// (none today) are left to their own handler.
    static func shouldFinish(productID: String, isVerified: Bool, tipProductIDs: Set<String>) -> Bool {
        isVerified && tipProductIDs.contains(productID)
    }

    // MARK: - Private

    private static func handle(
        _ result: VerificationResult<Transaction>,
        tipProductIDs: Set<String>,
        onTipCompleted: TipCompletionHandler
    ) async {
        switch result {
        case .verified(let transaction):
            guard shouldFinish(productID: transaction.productID, isVerified: true, tipProductIDs: tipProductIDs) else {
                Log.print.notice("[TipJar] Ignoring transaction for \(transaction.productID, privacy: .public)")
                return
            }
            await transaction.finish()
            Log.print.info("[TipJar] Finished background transaction for \(transaction.productID, privacy: .public)")
            // A refunded (revoked) tip doesn't count as a completed one.
            if transaction.revocationDate == nil {
                await onTipCompleted()
            }
        case .unverified(let transaction, let error):
            Log.print.error("[TipJar] Unverified background transaction for \(transaction.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
