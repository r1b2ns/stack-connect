import Foundation
import StackCoreRust

/// Turns Google Play connection errors into short, user-facing messages.
///
/// Inputs are whatever `GooglePlayAccountConnection` surfaces unchanged:
/// - `GooglePlayServiceAccount.ParseError` — the key file itself is unusable;
/// - `OfflineError` — the local "device is offline" guard;
/// - `StackError` from the Rust core. A quota or rate limit is always
///   `.Http(429, …)` (`GooglePlayQuota`), whatever the operation. Its
///   `errorDescription` is a debug string
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
        /// The developer account's users (`developers.users`): an HTTP 404 is
        /// a wrong developer ID, a 403 / `Auth` a service account without the
        /// Admin permission.
        case users
        /// Inviting a user: as `users`, plus a 409 (already a user or invited)
        /// and a 400 (typically an address that isn't a Google account).
        case inviteUser
        /// Changing or removing an existing user or app access: as `users`,
        /// except that a 404 means the user (or the access) is already gone.
        case userChange
    }

    /// - Parameters:
    ///   - authMethod: how the account calls Google Play. The copy names a
    ///     service account for `.keyFile` and the signed-in Google account for
    ///     `.googleSignIn`.
    ///   - accountEmail: that Google account's e-mail
    ///     (`GoogleLoginReferences.email(of:keychain:)`), named in the access
    ///     messages when known. Ignored for a service account.
    static func friendlyMessage(
        for error: Error,
        operation: Operation = .general,
        authMethod: AccountAuthMethod = .keyFile,
        accountEmail: String? = nil
    ) -> String {
        let caller = Caller(authMethod: authMethod, email: accountEmail)
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

        case .Auth(let message) where operation.isUsers:
            let lead: String
            switch caller {
            case .googleAccount(let email?):
                lead = String(localized: "To manage users, the Google account \(email) needs the “Admin (all permissions)” permission in Play Console › Users and permissions.",
                              comment: "Google Play users screen, account added with Sign in with Google. The placeholder is that Google account's e-mail.")
            case .googleAccount(nil):
                lead = String(localized: "To manage users, the signed-in Google account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")
            case .serviceAccount:
                lead = String(localized: "To manage users, this service account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")
            }
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"

        case .Auth(let message):
            let lead: String
            switch caller {
            case .googleAccount(let email?):
                lead = String(localized: "Google Play denied access to the Google account \(email).",
                              comment: "Lead sentence shown when Google rejects the account a user signed in with (Sign in with Google). The placeholder is that Google account's e-mail. It is followed by Google's own (English) instructions on how to fix it.")
            case .googleAccount(nil):
                lead = String(localized: "Google Play denied access to the signed-in Google account.",
                              comment: "Lead sentence shown when Google rejects the account a user signed in with (Sign in with Google). It is followed by Google's own (English) instructions on how to fix it.")
            case .serviceAccount:
                lead = String(localized: "Google Play denied access to this service account.")
            }
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"

        case .Network:
            return String(localized: "Couldn't reach Google Play. Check your internet connection and try again.")

        case .Http(429, let message):
            // A quota or rate limit, whatever the operation (the core reports
            // every one as 429, even when Google answered 403): never a
            // permission or developer ID problem.
            return quotaMessage(coreMessage: message)

        case .Http(let status, let message) where operation == .releaseChange:
            return releaseChangeMessage(status: Int(status), googleMessage: message, caller: caller)

        case .Http(let status, let message) where operation == .inviteUser && status == 400:
            return inviteRefusalMessage(googleMessage: message)

        case .Http(let status, let message) where operation.isUsers:
            // Keep the friendly lead and add the core's / Google's own text: a
            // wrong developer ID, a missing permission or a refused change
            // reads very differently in it (and a local check says nothing
            // was sent to Google at all).
            let lead = isLocalRejection(message) && status == 404
                ? GooglePlayDeveloperId.invalidMessage
                : httpMessage(status: Int(status), operation: operation, caller: caller)
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? lead : "\(lead)\n\(detail)"

        case .Http(let status, _):
            return httpMessage(status: Int(status), operation: operation, caller: caller)

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

        case .PendingAgreements, .SubmissionNotRemovable, .SessionExpired:
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

    /// A Google Play quota or rate limit: friendly copy, then Google's own text
    /// (without the core's explanation and request suffix) as the detail.
    private static func quotaMessage(coreMessage: String) -> String {
        let lead = String(localized: "Google Play's API quota for this account was reached. Wait a few minutes and try again.",
                          comment: "Error shown when Google Play answers with an API quota or rate limit (the core reports it as HTTP 429).")
        let detail = GooglePlayQuota.googleMessage(in: coreMessage)
        return detail.isEmpty ? lead : "\(lead)\n\(detail)"
    }

    /// Release changes: Google explains every refusal in its message, so the
    /// known ones get actionable copy and the rest show Google's text.
    private static func releaseChangeMessage(status: Int, googleMessage: String, caller: Caller) -> String {
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
            return httpMessage(status: status, operation: .releaseChange, caller: caller)
        }
    }

    /// A refused invitation: Google names an address that isn't a Google
    /// account; anything else shows Google's own text.
    private static func inviteRefusalMessage(googleMessage: String) -> String {
        let detail = googleMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = detail.lowercased()
        // The core's own check (an address it can't send, request not sent to
        // Google) is not Google refusing the account.
        if !isLocalRejection(detail),
           lowered.contains("google account") || lowered.contains("not a valid") || lowered.contains("invalid email") {
            return String(localized: "Google Play can only invite Google accounts. Check the address, or ask the person which Google account (Gmail or Google Workspace) to use.")
        }
        let lead = String(localized: "Google Play couldn't send this invitation.")
        return detail.isEmpty ? lead : "\(lead)\n\(detail)"
    }

    /// True for the error a wrong developer ID produces on the users list
    /// (HTTP 404, or a 403 that isn't about permissions), so the Users tab can
    /// offer to correct the ID (plan U3).
    static func isWrongDeveloperId(_ error: Error) -> Bool {
        guard case .Http(let status, _)? = error as? StackError else { return false }
        return status == 404 || status == 403
    }

    /// True when a users-list failure is worth answering by checking the
    /// developer ID, so the Users tab asks for it again, pre-filled with the
    /// stored value (plan U3): a wrong ID (`isWrongDeveloperId`, the core's
    /// local rejection of a non-numeric ID included), or Google refusing the
    /// developer account itself — its 403 reads the same for an ID the service
    /// account isn't a member of and for a member without the Admin permission.
    /// Other `Auth` failures (a revoked key, a disabled API) are not about the ID.
    static func asksForDeveloperId(_ error: Error) -> Bool {
        // A quota says nothing about the ID (the core reports it as 429).
        if GooglePlayQuota.isQuotaExceeded(error) { return false }
        if isWrongDeveloperId(error) { return true }
        guard case .Auth(let message)? = error as? StackError else { return false }
        return message.localizedCaseInsensitiveContains("cannot access the developer account")
    }

    /// True when the core refused the call before sending it (an invalid
    /// developer ID, e-mail, package name or release change): its message
    /// starts with "local validation failed:" and ends with "request not sent
    /// to Google". The core's older wording ("nothing was sent to Google") is
    /// still recognized, for safety.
    static func isLocalRejection(_ message: String) -> Bool {
        localRejectionMarkers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    private static let localRejectionMarkers = [
        "local validation failed",
        "request not sent to Google",
        "nothing was sent to Google"
    ]

    // MARK: - Technical details

    /// The "Technical details" lines of a shared error report for any Google
    /// Play error (see `GooglePlayErrorDetails`). Pass the users `call` for a
    /// `developers.users` failure: it adds the developer ID as stored, the
    /// resource path and the service account e-mail.
    static func technicalDetails(for error: Error, operation: Operation, call: GooglePlayUsersCall? = nil) -> [String] {
        GooglePlayErrorDetails(error: error, operation: call?.operation ?? operation, call: call).lines
    }

    /// A failed users call, ready for the screen: the friendly message, the
    /// report's technical details, and the failure logged under `logTag`.
    static func usersFailure(
        _ error: Error,
        call: GooglePlayUsersCall,
        logTag: String,
        authMethod: AccountAuthMethod = .keyFile,
        accountEmail: String? = nil
    ) -> GooglePlayUsersFailure {
        let details = GooglePlayErrorDetails(error: error, operation: call.operation, call: call)
        details.log(tag: logTag)
        return GooglePlayUsersFailure(
            message: friendlyMessage(for: error, operation: call.operation, authMethod: authMethod, accountEmail: accountEmail),
            technicalDetails: details.lines
        )
    }

    private static var genericMessage: String {
        String(localized: "Something went wrong while talking to Google Play. Try again.")
    }

    /// Who calls Google Play, as the copy names it.
    private enum Caller {
        case serviceAccount
        /// "Sign in with Google", with the account's e-mail when known.
        case googleAccount(email: String?)

        init(authMethod: AccountAuthMethod, email: String?) {
            switch authMethod {
            case .keyFile, .appleIdSignIn:
                self = .serviceAccount
            case .googleSignIn:
                let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
                self = .googleAccount(email: trimmed?.isEmpty == false ? trimmed : nil)
            }
        }
    }

    private static func httpMessage(status: Int, operation: Operation, caller: Caller) -> String {
        switch status {
        case 400 where operation == .replyToReview:
            return String(localized: "Google Play rejected this reply. Replies are limited to about \(GooglePlayReviewLimits.replyCharacterLimit) characters — shorten it and try again.")
        case 404 where operation == .userChange:
            return String(localized: "This user or app access is no longer on Google Play. Refresh and try again.")
        case 403 where operation.isUsers:
            switch caller {
            case .googleAccount(let email?):
                return String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the Google account \(email) has the “Admin (all permissions)” permission.",
                              comment: "Google Play users screen, account added with Sign in with Google. The placeholder is that Google account's e-mail.")
            case .googleAccount(nil):
                return String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the signed-in Google account has the “Admin (all permissions)” permission.")
            case .serviceAccount:
                return String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the service account has the “Admin (all permissions)” permission.")
            }
        case 404 where operation == .users || operation == .inviteUser:
            return String(localized: "Google Play found no developer account with this ID. Check the Developer ID in Play Console › Settings › Developer account.")
        case 409 where operation == .inviteUser:
            return String(localized: "This person already has access to this developer account or has a pending invitation.")
        case 403:
            // The core reports missing access as `.Auth`; a bare 403 is the same
            // problem without Google's detail.
            switch caller {
            case .googleAccount(let email?):
                return String(localized: "The Google account \(email) can't access this app. In Play Console › Users and permissions, give it access to the app and try again.",
                              comment: "Google Play error, account added with Sign in with Google. The placeholder is that Google account's e-mail.")
            case .googleAccount(nil):
                return String(localized: "The signed-in Google account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
            case .serviceAccount:
                return String(localized: "This service account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
            }
        case 404 where operation == .replyToReview:
            return String(localized: "This review is no longer available on Google Play.")
        case 404 where operation == .appContentRead, 404 where operation == .releaseChange:
            return String(localized: "Google Play couldn't load this information. Try again in a moment.")
        case 404:
            // Unknown package, or a package name that breaks Android's naming
            // rules (rejected by the core without a request).
            return String(localized: "Google Play found no app with this package name. Check it in Play Console and try again.")
        case 500...599:
            return String(localized: "Google Play is temporarily unavailable. Try again in a few minutes.")
        default:
            return String(localized: "Google Play returned an unexpected error (HTTP \(status)).")
        }
    }
}

private extension GooglePlayErrorTranslator.Operation {
    var isUsers: Bool {
        self == .users || self == .inviteUser || self == .userChange
    }
}

/// A failed Google Play users call as a screen shows it: the user-facing
/// message and the technical lines its Share Error report adds.
struct GooglePlayUsersFailure: Equatable, Sendable {
    let message: String
    var technicalDetails: [String] = []
}

/// Limits Google Play enforces on review replies.
enum GooglePlayReviewLimits {

    /// Google rejects replies longer than about this many characters (HTTP 400).
    /// Used as a soft limit: the composer warns, Google has the final word.
    static let replyCharacterLimit = 350
}
