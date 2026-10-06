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
///   appended after a localized lead sentence.
enum GooglePlayErrorTranslator {

    static func friendlyMessage(for error: Error) -> String {
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

        case .Http(let status, _):
            return httpMessage(status: Int(status))

        case .Decode:
            return String(localized: "Google Play returned an unexpected response. Try again later.")

        case .Unsupported:
            return String(localized: "This action isn't available for Google Play accounts yet.")

        case .PendingAgreements, .SubmissionNotRemovable:
            // App Store Connect–only cases; never expected from the Play provider.
            return genericMessage
        }
    }

    /// True for the local offline guard and for core transport failures — the
    /// cases where cached data is still the best thing to show.
    static func isOffline(_ error: Error) -> Bool {
        if case OfflineError.noConnection = error { return true }
        if case StackError.Network = error { return true }
        return false
    }

    // MARK: - Private

    private static var genericMessage: String {
        String(localized: "Something went wrong while talking to Google Play. Try again.")
    }

    private static func httpMessage(status: Int) -> String {
        switch status {
        case 429:
            return String(localized: "You hit Google's rate limit. Wait a moment and try again.")
        case 500...599:
            return String(localized: "Google Play is temporarily unavailable. Try again in a few minutes.")
        default:
            return String(localized: "Google Play returned an unexpected error (HTTP \(status)).")
        }
    }
}
