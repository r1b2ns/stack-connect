import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

#if canImport(os)
import os
#endif

// T-W24 — Reply Composer model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides:
// - Editor text state with dirty tracking (text differs from initial body)
// - Submit (upsert) reply via AppleConnectionProtocol
// - isPending flag for loading state
// - canSubmit flag (non-empty + non-pending)
// - didSucceed flag for signalling pop-back after successful submit
//
// Mirrors `WindowsReviewDetailModel` conventions: `@MainActor`,
// `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI via init
// (`storage: PersistentStorable`, optional `connection`), error-field naming,
// `#if canImport(os)` logging.
//
// The upsert + persistence logic intentionally mirrors
// `WindowsReviewDetailModel.sendReply` to keep detail + composer consistent.
// For create: existingResponseId is nil; for edit: the model resolves the
// existing responseId from the cached review at init time.

// MARK: - Model

/// Reply Composer model. Owns the state the Reply Composer view binds to and
/// exposes intents for submitting (creating or editing) a developer response
/// to a customer review.
@MainActor
public final class WindowsReplyComposerModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// The editor text. Pre-populated with `existingReplyBody` for edit mode.
    @SwiftCrossUI.Published public var text: String

    /// True while a reply upsert operation is in flight.
    @SwiftCrossUI.Published public private(set) var isPending: Bool = false

    /// Non-nil when a reply mutation fails. The view shows this as an error
    /// message and keeps the composer open for retry (TC-043; AC-W13-4).
    @SwiftCrossUI.Published public private(set) var error: String?

    /// Set to `true` after a successful submit. The view observes this to
    /// trigger a pop-back to the review detail screen (TC-034/036).
    @SwiftCrossUI.Published public private(set) var didSucceed: Bool = false

    // MARK: - Read-Only Computed Properties

    /// Whether the Submit button should be enabled: non-empty text and not
    /// currently pending (AC-W13-1).
    public var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPending
    }

    /// Whether the editor content differs from the initial/existing body.
    /// Supports the dirty-state guard (discard confirmation on back).
    public var isDirty: Bool {
        text != initialBody
    }

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?
    private let reviewId: String
    private let accountId: String
    private let initialBody: String
    private let existingResponseId: String?

    // MARK: - Init

    /// Creates a new reply composer model.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - accountId: The owning account identifier.
    ///   - existingReplyBody: The existing reply body text, or `nil` for create
    ///     mode. When non-nil, the editor is pre-populated and
    ///     `existingResponseId` is resolved from the cached review (AC-W13-5).
    ///   - existingResponseId: The existing response identifier for edit mode,
    ///     or `nil` for create mode. When provided explicitly it overrides cache
    ///     resolution. Exposed primarily for testability.
    ///   - storage: Persistent storage backend.
    ///   - connection: Optional Apple connection for the upsert API call.
    ///     When nil, submit will fail with "No connection available."
    public init(
        reviewId: String,
        accountId: String,
        existingReplyBody: String?,
        existingResponseId: String? = nil,
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.reviewId = reviewId
        self.accountId = accountId
        self.initialBody = existingReplyBody ?? ""
        self.text = existingReplyBody ?? ""
        self.existingResponseId = existingResponseId
        self.storage = storage
        self.connection = connection
    }

    // MARK: - Resolve Existing Response ID from Cache

    /// Resolves the existing responseId from the cached review if not provided
    /// at init. Called by the view on appear to ensure edit mode has the correct
    /// responseId before the user submits.
    ///
    /// Returns the responseId from init if provided, otherwise fetches the
    /// cached review and returns its responseId (may be nil if the review has
    /// no existing response in cache).
    public func resolveExistingResponseId() async -> String? {
        // If explicitly provided at init, use that.
        if let existingResponseId {
            return existingResponseId
        }

        // Resolve from cache (for edit mode where only the body was passed).
        do {
            if let review = try await storage.fetch(CustomerReviewModel.self, id: reviewId) {
                return review.responseId
            }
        } catch {
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ReplyComposer")
                .warning("[ReplyComposer] Failed to resolve responseId from cache for review \(self.reviewId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
        }
        return nil
    }

    // MARK: - Submit Reply (AC-W13-1..6)

    /// Creates a new reply or updates an existing reply for the review.
    ///
    /// In create mode (`responseId` is nil), performs a create upsert.
    /// In edit mode (`responseId` is non-nil), performs an update upsert
    /// (delete-then-create per T-W01).
    ///
    /// On success: persists the updated review (matching
    /// `WindowsReviewDetailModel.sendReply` shape), sets `didSucceed = true`
    /// so the view can pop. On failure: sets `error`, does NOT persist or
    /// signal pop (AC-W13-4; TC-043).
    ///
    /// - Parameter responseBody: The text of the reply to create or update.
    public func submitReply(responseBody: String) async {
        guard let connection else {
            error = "No connection available."
            return
        }

        isPending = true
        error = nil

        // Resolve the existing responseId (nil for create, non-nil for edit).
        let resolvedResponseId = await resolveExistingResponseId()

        do {
            try await connection.upsertReply(
                reviewId: reviewId,
                existingResponseId: resolvedResponseId,
                responseBody: responseBody
            )

            // Success: persist the updated review exactly as
            // WindowsReviewDetailModel.sendReply does (AC-W13-3/6).
            do {
                var updatedReview: CustomerReviewModel
                if let cached = try await storage.fetch(CustomerReviewModel.self, id: reviewId) {
                    updatedReview = cached
                } else {
                    // No cached review — construct a minimal one for persistence.
                    updatedReview = CustomerReviewModel(id: reviewId, rating: 0)
                }

                updatedReview.responseBody = responseBody
                updatedReview.responseState = "PENDING_PUBLISH"
                updatedReview.responseDate = Date()

                if resolvedResponseId == nil {
                    // Create: assign a local placeholder ID until the next sync
                    // surfaces the real server-assigned ID.
                    updatedReview.responseId = "local-\(reviewId)"
                }
                // Edit: responseId stays the same (resolvedResponseId).

                try await storage.save(updatedReview, id: reviewId)
            } catch {
                // Persistence failure after successful API call: log but still
                // signal success (the server has the reply; next sync will
                // reconcile cache).
                #if canImport(os)
                Logger(subsystem: "com.stackconnect.windows", category: "ReplyComposer")
                    .warning("[ReplyComposer] Persistence failed after successful upsert for review \(self.reviewId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                #endif
            }

            isPending = false
            didSucceed = true

        } catch {
            // AC-W13-4/TC-043: On failure, do NOT persist or signal pop.
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ReplyComposer")
                .warning("[ReplyComposer] Submit reply failed for review \(self.reviewId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            self.error = "Failed to save reply."
            isPending = false
        }
    }
}
