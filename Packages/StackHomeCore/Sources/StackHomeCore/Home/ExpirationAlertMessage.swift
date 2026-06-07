import Foundation

/// Foundation-pure message builders for the account-expiration alerts (US-005).
///
/// The exact alert copy lives here (not in the platform views) so it is shared by
/// iOS and the Windows port and is unit-testable without a GUI (TC-022). The
/// Windows banner and the iOS alert both call these to get the strings; the views
/// stay dumb and re-derive no expiration/date logic.
///
/// Windows v1 is hardcoded English per the refinement (localization out of
/// scope), so the literals here are plain strings.
public enum ExpirationAlertMessage {

    /// The expired-account message (US-005 AC-1).
    public static func expired(accountName: String) -> String {
        "The account \"\(accountName)\" has expired. Re-import its file to keep using it, or it will stay locked."
    }

    /// The date-aware expiring-soon message (US-005 AC-4). When the expiration
    /// date is known it is included (abbreviated date + short time); otherwise a
    /// date-less fallback is used.
    public static func expiringSoon(accountName: String, expirationDate: Date?) -> String {
        if let expirationDate {
            let formatted = formattedExpiration(expirationDate)
            return "The account \"\(accountName)\" will expire on \(formatted). Request a new file from the administrator before then."
        }
        return "The account \"\(accountName)\" will expire soon. Request a new file from the administrator."
    }

    /// Formats an expiration date as an abbreviated date + short time.
    ///
    /// `Date.formatted(date:time:)` (the `FormatStyle` API) is Apple-only and
    /// absent from swift-corelibs-foundation used by the Windows/Linux toolchain,
    /// so the non-Darwin build uses a `DateFormatter` with an equivalent
    /// medium-date / short-time style. Mirrors the cross-platform guard used by
    /// the widget views.
    static func formattedExpiration(_ date: Date) -> String {
        #if canImport(Darwin)
        return date.formatted(date: .abbreviated, time: .shortened)
        #else
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
        #endif
    }
}
