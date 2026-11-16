import Foundation
import StackCoreRust

/// Turns Google Play connection errors into short, user-facing messages.
///
/// Inputs are whatever `GooglePlayAccountConnection` surfaces unchanged:
/// - `GooglePlayServiceAccount.ParseError` — the key file itself is unusable;
/// - `OfflineError` — the local "device is offline" guard;
/// - `StackError` from the Rust core. Its `errorDescription` is a debug string
///   (`String(reflecting:)`), so it is never shown raw. The one exception is the
///   `.Auth` message: the core fills it with actionable English guidance from
///   Google (enable the Reporting API + activation URL, invite the service
///   account in Play Console, missing scope, `invalid_grant` hints), so it is
///   appended after a localized lead sentence. For the app-content and review
///   calls it also names the app and the Play Console permission it needs.
enum GooglePlayErrorTranslator {

    /// What the failed call was doing, for statuses whose meaning depends on it.
    enum Operation {
        /// Listing apps, checking a package by hand, listing reviews: an HTTP
        /// 404 means Google knows no app with that package name.
        case general
        /// An edit-based read (app details, store listings, tracks). An HTTP 404
        /// here can also be the temporary edit itself, invalidated by another
        /// edit for the same app, so it's not reported as an unknown package.
        case appContentRead
        /// `replyToReview`: an HTTP 400 is Google rejecting the reply text
        /// (typically longer than about 350 characters); an HTTP 404 is a review
        /// Google no longer shares (deleted, or out of its 7-day window).
        case replyToReview
        /// `applyReleaseChange` (a committed edit): a refusal carries Google's
        /// own validation message, which is the only useful detail.
        case releaseChange
    }

    static func friendlyMessage(for error: Error, operation: Operation = .general) -> String {
        if let parseError = error as? GooglePlayServiceAccount.ParseError {
            return parseError.localizedDescription
        }
        if let offlineError = error as? OfflineError {
            return offlineError.localizedDescription
        }
        guard let stackError = error as? StackError else {
            return error.localizedDescription
        }

        switch stackError {
        case .InvalidCredentials:
            // The core's detail is about key parsing internals — not actionable.
            return String(localized: "The service account key is invalid. Download a new JSON key from Google Cloud and try again.")

        case .Auth(let message):
            let lead = String(localized: "Google Play denied access to this service account.")
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"

        case .Network:
            return String(localized: "Couldn't reach Google Play. Check your internet connection and try again.")

        case .Http(let status, let message) where operation == .releaseChange:
            return releaseChangeMessage(status: Int(status), googleMessage: message)

        case .Http(let status, _):
            return httpMessage(status: Int(status), operation: operation)

        case .Decode:
            return String(localized: "Google Play returned an unexpected response. Try again later.")

        case .Unsupported:
            // e.g. deleting a review reply or sorting reviews other than newest
            // first: Google Play's API has no equivalent.
            return String(localized: "Google Play doesn't support this action.")

        case .ReleaseNotFound:
            // A track change targeted a release someone else replaced, completed
            // or removed since the track was read. Nothing was changed.
            return String(localized: "This release changed on Google Play since it was loaded. Refresh and try again.")

        case .PendingAgreements, .SubmissionNotRemovable:
            // App Store Connect–only cases; never expected from the Play provider.
            return genericMessage
        }
    }

    /// True for the local offline guard and for core transport failures — the
    /// cases where cached data is still the best thing to show.
    static func isOffline(_ error: Error) -> Bool {
        OfflineError.isConnectivityFailure(error)
    }

    /// Google's own message for a refused release change (validation or
    /// commit failure), for the checklist's error block and its Share Error.
    /// `nil` for anything that isn't a refusal by Google.
    static func googleMessage(for error: Error) -> String? {
        guard case .Http(let status, let message)? = error as? StackError, (400..<500).contains(Int(status)) else {
            return nil
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Private

    /// Release changes: Google explains every refusal in its message, so the
    /// known ones get actionable copy and the rest show Google's text.
    private static func releaseChangeMessage(status: Int, googleMessage: String) -> String {
        let detail = googleMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = detail.lowercased()
        if lowered.contains("changesnotsentforreview") || lowered.contains("not be sent for review")
            || lowered.contains("must not be sent") {
            return String(localized: "Google Play requires these changes to be saved without sending them for review. Turn off “Send changes for review” and try again.")
        }
        if lowered.contains("in review") || lowered.contains("in_review") || lowered.contains("being reviewed") {
            return String(localized: "Another change to this app is in review. Choose “Cancel review and resubmit” under “If a review is in progress”, or try again when the review ends.")
        }
        switch status {
        case 400, 409, 412, 422:
            let lead = String(localized: "Google Play rejected this change. Nothing was published.")
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"
        default:
            return httpMessage(status: status, operation: .releaseChange)
        }
    }

    private static var genericMessage: String {
        String(localized: "Something went wrong while talking to Google Play. Try again.")
    }

    private static func httpMessage(status: Int, operation: Operation) -> String {
        switch status {
        case 400 where operation == .replyToReview:
            return String(localized: "Google Play rejected this reply. Replies are limited to about \(GooglePlayReviewLimits.replyCharacterLimit) characters — shorten it and try again.")
        case 403:
            // The core reports missing access as `.Auth`; a bare 403 is the same
            // problem without Google's detail.
            return String(localized: "This service account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        case 404 where operation == .replyToReview:
            return String(localized: "This review is no longer available on Google Play.")
        case 404 where operation == .appContentRead, 404 where operation == .releaseChange:
            return String(localized: "Google Play couldn't load this information. Try again in a moment.")
        case 404:
            // Unknown package, or a package name that breaks Android's naming
            // rules (rejected by the core without a request).
            return String(localized: "Google Play found no app with this package name. Check it in Play Console and try again.")
        case 429:
            return String(localized: "You hit Google's rate limit. Wait a moment and try again.")
        case 500...599:
            return String(localized: "Google Play is temporarily unavailable. Try again in a few minutes.")
        default:
            return String(localized: "Google Play returned an unexpected error (HTTP \(status)).")
        }
    }
}

/// Limits Google Play enforces on review replies.
enum GooglePlayReviewLimits {

    /// Google rejects replies longer than about this many characters (HTTP 400).
    /// Used as a soft limit: the composer warns, Google has the final word.
    static let replyCharacterLimit = 350
}
