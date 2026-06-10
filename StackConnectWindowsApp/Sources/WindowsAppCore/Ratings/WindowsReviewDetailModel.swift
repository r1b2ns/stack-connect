import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

#if canImport(os)
import os
#endif

// T-W22 — Review Detail model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides:
// - Full review display data (stars, date+time, title, body, nickname, territory)
// - Reply state management (create/edit mode with contextual button label)
// - Upsert reply via sendReply (create or edit via AppleConnectionProtocol)
// - Delete reply
// - Copy formatted review text to clipboard
//
// Mirrors `WindowsRatingsReviewsModel` / `WindowsAppDetailModel` conventions:
// `@MainActor`, `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI
// via init (`storage: PersistentStorable`, optional `connection`, clipboard),
// offline-first cache load with live sync + cache fallback on network error.
//
// The model is PURE testable logic — no SwiftCrossUI View imports, no
// singletons. The clipboard dependency is injectable via a protocol so tests
// can verify copy behavior without Win32 APIs.

// MARK: - Clipboard Protocol (DI seam for testability)

/// Injectable clipboard interface so `WindowsReviewDetailModel` can be
/// unit-tested without depending on the Win32 clipboard APIs.
public protocol ClipboardProviding: Sendable {
    /// Writes text to the system clipboard.
    /// - Returns: `true` if the text was successfully written.
    func setText(_ text: String) -> Bool
}

/// Default clipboard provider that delegates to `WindowsClipboard.setText`.
public struct SystemClipboardProvider: ClipboardProviding {
    public init() {}

    public func setText(_ text: String) -> Bool {
        WindowsClipboard.setText(text)
    }
}

// MARK: - Reply Mode

/// Describes whether the review currently has a reply (edit mode) or not
/// (create mode). Drives the button label and upsert behavior.
public enum ReviewReplyMode: Equatable, Sendable {
    /// No existing reply — the user can write a new one.
    case create
    /// An existing reply is present — the user can edit or delete it.
    case edit(responseId: String)

    /// The label for the primary reply action button.
    public var buttonLabel: String {
        switch self {
        case .create: return "Write a Reply"
        case .edit:   return "Edit Reply"
        }
    }
}

// MARK: - UI State

/// The complete UI state for the Review Detail screen.
public struct ReviewDetailUiState {

    // MARK: Review Display (AC-W12-1)

    /// The loaded review (nil before first load).
    public var review: CustomerReviewModel?

    /// True while the review is loading (cache fetch or live sync).
    public var isLoading: Bool = false

    /// Non-nil when a load or sync operation fails; the cached review
    /// remains visible (cache fallback). Cleared on next load attempt.
    public var syncError: String?

    // MARK: Reply State (AC-W12-2/3)

    /// The current reply mode derived from the review's response fields.
    /// `.create` → "Write a Reply" + helper text; `.edit` → reply body+date +
    /// Edit/Delete affordances.
    public var replyMode: ReviewReplyMode = .create

    /// The existing reply body text (nil when in create mode).
    public var existingReplyBody: String?

    /// The existing reply date (nil when in create mode).
    public var existingReplyDate: Date?

    // MARK: Reply Mutation (AC-W13-1..9)

    /// True while a reply upsert or delete operation is in flight.
    /// Drives a pending/loading indicator on the reply action buttons.
    public var isReplyPending: Bool = false

    /// Non-nil when a reply mutation (upsert or delete) fails. The view
    /// can display this as a non-blocking error message.
    public var replyError: String?

    // MARK: Clipboard (AC-W14-1/2)

    /// Transient confirmation or error message after a clipboard operation.
    /// Auto-dismissed after a short delay, or cleared manually.
    public var clipboardMessage: String?

    public init(
        review: CustomerReviewModel? = nil,
        isLoading: Bool = false,
        syncError: String? = nil,
        replyMode: ReviewReplyMode = .create,
        existingReplyBody: String? = nil,
        existingReplyDate: Date? = nil,
        isReplyPending: Bool = false,
        replyError: String? = nil,
        clipboardMessage: String? = nil
    ) {
        self.review = review
        self.isLoading = isLoading
        self.syncError = syncError
        self.replyMode = replyMode
        self.existingReplyBody = existingReplyBody
        self.existingReplyDate = existingReplyDate
        self.isReplyPending = isReplyPending
        self.replyError = replyError
        self.clipboardMessage = clipboardMessage
    }
}

// MARK: - Model

/// Review Detail model. Owns the state the Review Detail view binds to and
/// exposes intents for loading the review, creating/editing/deleting replies,
/// and copying the review text to the clipboard.
@MainActor
public final class WindowsReviewDetailModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    @SwiftCrossUI.Published public private(set) var uiState = ReviewDetailUiState()

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?
    private let clipboard: ClipboardProviding
    private let clipboardAutoDismissDelay: UInt64

    // MARK: - Clipboard Auto-Dismiss

    /// Cancellable task for the clipboard message auto-dismiss timer.
    /// Typed as `Task<Void, Error>` so that cancellation propagates via
    /// `CancellationError` from `Task.sleep` and the clear-line is never
    /// reached after cancellation (no anti-pattern `try?` + `guard`).
    private var clipboardDismissTask: Task<Void, Error>?

    // MARK: - Init

    /// Creates a new review detail model.
    ///
    /// - Parameters:
    ///   - storage: Persistent storage backend.
    ///   - connection: Optional Apple connection for live sync and reply
    ///     mutations. When nil, only cached data is shown.
    ///   - clipboard: Clipboard provider for copy operations. Defaults to
    ///     `SystemClipboardProvider()` which delegates to `WindowsClipboard`.
    ///   - clipboardAutoDismissDelay: Nanoseconds before the clipboard
    ///     confirmation message auto-dismisses. Defaults to 2 seconds
    ///     (2_000_000_000 ns). Injectable so T-W26 tests can pass a tiny
    ///     or zero delay to assert deterministically.
    public init(
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil,
        clipboard: ClipboardProviding = SystemClipboardProvider(),
        clipboardAutoDismissDelay: UInt64 = 2_000_000_000
    ) {
        self.storage = storage
        self.connection = connection
        self.clipboard = clipboard
        self.clipboardAutoDismissDelay = clipboardAutoDismissDelay
    }

    // MARK: - Load Review (Offline-First + Live Sync + Cache Fallback)

    /// Loads the review from cache first, then optionally live-syncs from the
    /// API. On network error, the cached review remains visible and
    /// `uiState.syncError` is set (cache fallback — TC-042).
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - appId: The App Store app identifier (for fetching reviews from API).
    ///   - accountId: The account identifier (for storage key context).
    public func loadReviewIfNeeded(reviewId: String, appId: String, accountId: String) async {
        uiState.isLoading = true
        uiState.syncError = nil
        uiState.replyError = nil

        // Phase 1: Load from cache (offline-first — TC-032)
        var cachedReview: CustomerReviewModel?
        do {
            cachedReview = try await storage.fetch(CustomerReviewModel.self, id: reviewId)
        } catch {
            // Cache load failure: not fatal; proceed to live sync.
            cachedReview = nil
        }

        if let cachedReview {
            uiState.review = cachedReview
            applyReplyState(from: cachedReview)
        }

        // Phase 2: Live sync
        guard let connection else {
            uiState.isLoading = false
            return
        }

        do {
            // Known limitation: fetchReviews returns a single ReviewsPage
            // (up to ~50 reviews). If the target review is not on this first
            // page, live sync will not find it and the cached copy is shown
            // indefinitely. This is acceptable because the detail view is
            // always opened from an already-loaded list item, so the cache
            // holds the correct data. Pagination for live-sync is out of
            // scope for T-W22.
            let page = try await connection.fetchReviews(appId: appId)
            if let liveReview = page.reviews.first(where: { $0.id == reviewId }) {
                uiState.review = liveReview
                applyReplyState(from: liveReview)

                // Persist the synced review
                try await storage.save(liveReview, id: reviewId)
            }
        } catch {
            // TC-042: Network error cache fallback — cached review remains,
            // error banner surfaced as non-blocking.
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ReviewDetail")
                .warning("[ReviewDetail] Live sync failed for review \(reviewId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            if uiState.review != nil {
                uiState.syncError = "Sync failed. Showing cached data."
            } else {
                uiState.syncError = "Failed to load review."
            }
        }

        uiState.isLoading = false
    }

    // MARK: - Send Reply / Upsert (AC-W13-1..6)

    /// Creates a new reply or updates an existing reply for the loaded review.
    ///
    /// In create mode (no existing response), performs a create upsert.
    /// In edit mode (existing responseId), performs an update upsert
    /// (delete-then-create per T-W01).
    ///
    /// On success: updates the review's response fields in state and persists
    /// the updated review. On failure: sets `replyError` and does NOT persist
    /// or partially mutate the review (AC-W13-4/AC-W13-6).
    ///
    /// - Parameter responseBody: The text of the reply to create or update.
    ///   The caller should disable the submit button on empty input
    ///   (AC-W13-1 boundary).
    public func sendReply(responseBody: String) async {
        guard let review = uiState.review else { return }
        guard let connection else {
            uiState.replyError = "No connection available."
            return
        }

        uiState.isReplyPending = true
        uiState.replyError = nil

        let existingResponseId: String?
        switch uiState.replyMode {
        case .create:
            existingResponseId = nil
        case .edit(let responseId):
            existingResponseId = responseId
        }

        do {
            try await connection.upsertReply(
                reviewId: review.id,
                existingResponseId: existingResponseId,
                responseBody: responseBody
            )

            // Success: update the review model with the new reply data.
            // The API does not return the created response entity, so we
            // construct the updated state locally. For a create, we generate
            // a placeholder responseId (the next load will fetch the real one);
            // for an edit, we keep the existing responseId.
            var updatedReview = review
            updatedReview.responseBody = responseBody
            updatedReview.responseState = "PENDING_PUBLISH"
            updatedReview.responseDate = Date()

            if existingResponseId == nil {
                // Create: assign a local placeholder ID until the next sync
                // surfaces the real server-assigned ID.
                //
                // NOTE: If the user deletes this reply before the next
                // successful sync, `deleteReply()` sends this "local-*" id
                // to the API, which will fail because the server does not
                // recognize it. That failure is handled gracefully via
                // `replyError` (the user sees "Failed to delete reply" and
                // the reply remains visible until the next sync reconciles
                // state). Full sync-after-create is out of scope for T-W22.
                updatedReview.responseId = "local-\(review.id)"
            }
            // Edit: responseId stays the same (existingResponseId).

            uiState.review = updatedReview
            applyReplyState(from: updatedReview)

            // Persist the updated review (AC-W13-2/AC-W13-5)
            try await storage.save(updatedReview, id: review.id)
        } catch {
            // AC-W13-4/AC-W13-6: On failure, do NOT leave a partial reply.
            // The previous state is preserved (review unchanged).
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ReviewDetail")
                .warning("[ReviewDetail] Send reply failed for review \(review.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            uiState.replyError = "Failed to save reply."
        }

        uiState.isReplyPending = false
    }

    // MARK: - Delete Reply (AC-W13-7..9)

    /// Deletes the existing reply for the loaded review. Requires the current
    /// review to have an existing response (responseId derived from state).
    ///
    /// On success: removes the reply from state (restoring create/"Write a
    /// Reply" mode) and persists the updated review. On failure: keeps the
    /// reply visible and sets `replyError` — does NOT pop or clear state.
    public func deleteReply() async {
        guard let review = uiState.review else { return }

        // Extract the responseId from the current reply mode.
        guard case .edit(let responseId) = uiState.replyMode else {
            // No existing reply to delete (already in create mode).
            return
        }

        guard let connection else {
            uiState.replyError = "No connection available."
            return
        }

        uiState.isReplyPending = true
        uiState.replyError = nil

        do {
            try await connection.deleteReply(responseId: responseId)

            // Success: clear reply fields and restore create mode (AC-W13-7).
            var updatedReview = review
            updatedReview.responseId = nil
            updatedReview.responseBody = nil
            updatedReview.responseState = nil
            updatedReview.responseDate = nil

            uiState.review = updatedReview
            applyReplyState(from: updatedReview)

            // Persist the updated review (AC-W13-8)
            try await storage.save(updatedReview, id: review.id)
        } catch {
            // AC-W13-9: On failure, keep the reply and set an error.
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "ReviewDetail")
                .warning("[ReviewDetail] Delete reply failed for response \(responseId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            uiState.replyError = "Failed to delete reply."
        }

        uiState.isReplyPending = false
    }

    // MARK: - Copy Review to Clipboard (AC-W14-1/2)

    /// Formats the loaded review's text and copies it to the clipboard.
    ///
    /// The formatted text includes the rating (as stars), title, body,
    /// nickname, territory, and date. On success, sets a "Copied!"
    /// confirmation message (TC-040). On an unsupported host (macOS dev
    /// machine where `WindowsClipboard.setText` returns false), sets the
    /// graceful fallback "Clipboard not available on this host" (TC-041).
    ///
    /// The confirmation message auto-dismisses after 2 seconds via a
    /// cancellable `Task.sleep` timer.
    public func copyReviewToClipboard() {
        guard let review = uiState.review else { return }

        let formatted = formatReviewForClipboard(review)
        let success = clipboard.setText(formatted)

        if success {
            uiState.clipboardMessage = "Copied!"
        } else {
            uiState.clipboardMessage = "Clipboard not available on this host"
        }

        // Auto-dismiss the clipboard message after the configured delay.
        // Cancellation propagates naturally: a cancelled Task.sleep throws
        // CancellationError, so the clear-line is never reached.
        clipboardDismissTask?.cancel()
        clipboardDismissTask = Task { [weak self] in
            try await Task.sleep(nanoseconds: self?.clipboardAutoDismissDelay ?? 2_000_000_000)
            self?.uiState.clipboardMessage = nil
        }
    }

    /// Clears the transient clipboard message (e.g. after the view has
    /// shown the confirmation). Also cancels any pending auto-dismiss timer.
    public func clearClipboardMessage() {
        clipboardDismissTask?.cancel()
        clipboardDismissTask = nil
        uiState.clipboardMessage = nil
    }

    // MARK: - Private Helpers

    /// Derives the reply-related UI state from the review's response fields.
    /// Drives AC-W12-2 (no reply → create mode) and AC-W12-3 (existing reply
    /// → edit mode with body + date).
    ///
    /// The canonical "reply exists" arbiter is `responseId != nil` (the
    /// persistent server identifier), NOT `hasResponse` (which checks
    /// responseBody non-empty). A review can have a responseId with an empty
    /// body during PENDING_PUBLISH transitions; gating on `hasResponse` would
    /// wrongly enter `.create` mode and a subsequent `sendReply` would upsert
    /// with `existingResponseId = nil`, creating a DUPLICATE on the server.
    /// Any "should I show the reply text" gating on responseBody belongs in
    /// the view layer.
    private func applyReplyState(from review: CustomerReviewModel) {
        if let responseId = review.responseId {
            uiState.replyMode = .edit(responseId: responseId)
            uiState.existingReplyBody = review.responseBody
            uiState.existingReplyDate = review.responseDate
        } else {
            uiState.replyMode = .create
            uiState.existingReplyBody = nil
            uiState.existingReplyDate = nil
        }
    }

    /// Formats a review into a human-readable clipboard text including
    /// rating stars, title, body, reviewer info, territory, and date.
    private func formatReviewForClipboard(_ review: CustomerReviewModel) -> String {
        let stars = String(repeating: "\u{2605}", count: review.rating)
            + String(repeating: "\u{2606}", count: max(0, 5 - review.rating))

        var lines: [String] = []
        lines.append(stars)

        if let title = review.title, !title.isEmpty {
            lines.append(title)
        }

        if let body = review.body, !body.isEmpty {
            lines.append(body)
        }

        var metaParts: [String] = []
        if let nickname = review.reviewerNickname, !nickname.isEmpty {
            metaParts.append("by \(nickname)")
        }
        if let territory = review.territory, !territory.isEmpty {
            metaParts.append(review.territoryDisplayName)
        }
        if let date = review.createdDate {
            metaParts.append(WindowsDateFormatting.absoluteDate(date))
        }

        if !metaParts.isEmpty {
            lines.append("-- " + metaParts.joined(separator: " | "))
        }

        return lines.joined(separator: "\n")
    }
}
