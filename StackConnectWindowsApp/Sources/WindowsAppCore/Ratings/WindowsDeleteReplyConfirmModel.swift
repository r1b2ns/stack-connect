import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

#if canImport(os)
import os
#endif

// T-W25 — Delete Reply Confirm model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides:
// - isPending flag for loading state
// - error field for user-facing failure messages
// - didSucceed flag for signalling pop-back after successful delete
//
// Mirrors `WindowsReplyComposerModel` conventions: `@MainActor`,
// `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI via init
// (`storage: PersistentStorable`, optional `connection`), error-field naming,
// `#if canImport(os)` logging.
//
// The delete + persistence logic mirrors
// `WindowsReviewDetailModel.deleteReply` to keep detail + confirm consistent.

// MARK: - Model

/// Delete Reply Confirm model. Owns the state the Delete Reply Confirm view
/// binds to and exposes the intent for confirming a developer response deletion.
@MainActor
public final class WindowsDeleteReplyConfirmModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// True while a delete operation is in flight.
    @SwiftCrossUI.Published public private(set) var isPending: Bool = false

    /// Non-nil when a delete fails. The view shows this as an error message
    /// and keeps the confirmation screen open for retry (AC-W13-9).
    @SwiftCrossUI.Published public private(set) var error: String?

    /// Set to `true` after a successful delete. The view observes this to
    /// trigger a pop-back to the review detail screen (AC-W13-8).
    @SwiftCrossUI.Published public private(set) var didSucceed: Bool = false

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?
    private let reviewId: String
    private let responseId: String
    private let accountId: String

    // MARK: - Init

    /// Creates a new delete reply confirm model.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - responseId: The server-assigned response identifier to delete.
    ///   - accountId: The owning account identifier.
    ///   - storage: Persistent storage backend.
    ///   - connection: Optional Apple connection for the delete API call.
    ///     When nil, confirm will fail with "No connection available."
    public init(
        reviewId: String,
        responseId: String,
        accountId: String,
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.reviewId = reviewId
        self.responseId = responseId
        self.accountId = accountId
        self.storage = storage
        self.connection = connection
    }

    // MARK: - Confirm Delete (AC-W13-7..9)

    /// Deletes the developer response identified by `responseId`.
    ///
    /// On success: calls `connection.deleteReply(responseId:)`, then clears the
    /// reply fields (responseId, responseBody, responseState, responseDate) on
    /// the cached review and persists the updated review. Sets `didSucceed = true`
    /// so the view pops back to the review detail (AC-W13-8).
    ///
    /// On failure: sets `error` with a user-facing message, does NOT mutate
    /// storage, does NOT set `didSucceed` — the screen stays open for retry
    /// (AC-W13-9).
    public func deleteReplyConfirmed() async {
        guard let connection else {
            error = "No connection available."
            return
        }

        isPending = true
        error = nil

        do {
            try await connection.deleteReply(responseId: responseId)

            // Success: clear reply fields on the cached review and persist.
            do {
                if var cachedReview = try await storage.fetch(CustomerReviewModel.self, id: reviewId) {
                    cachedReview.responseId = nil
                    cachedReview.responseBody = nil
                    cachedReview.responseState = nil
                    cachedReview.responseDate = nil
                    try await storage.save(cachedReview, id: reviewId)
                }
            } catch {
                // Persistence failure after successful API call: log but still
                // signal success (the server has deleted the reply; next sync
                // will reconcile cache).
                #if canImport(os)
                Logger(subsystem: "com.stackconnect.windows", category: "DeleteReplyConfirm")
                    .warning("[DeleteReplyConfirm] Persistence failed after successful delete for review \(self.reviewId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                #endif
            }

            isPending = false
            didSucceed = true

        } catch {
            // AC-W13-9: On failure, keep the reply and set an error.
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "DeleteReplyConfirm")
                .warning("[DeleteReplyConfirm] Delete reply failed for response \(self.responseId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            self.error = "Failed to delete reply."
            isPending = false
        }
    }
}
