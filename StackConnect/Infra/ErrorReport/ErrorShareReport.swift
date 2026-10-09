import Foundation

// MARK: - Context

/// Where an error happened, as shown on screen: what an error report needs to
/// tell the recipient (e.g. whoever administers the Google Cloud project or the
/// Play Console) which screen, store, account and app failed.
///
/// Holds display values only — never credentials, tokens, key ids or keychain
/// data.
struct ErrorReportContext: Equatable, Sendable {

    /// Screen title (e.g. "Ratings & Reviews").
    var screen: String
    /// Store / provider display name (e.g. "Google Play").
    var store: String?
    /// Account display name.
    var accountName: String?
    /// App display name.
    var appName: String?
    /// Bundle id (App Store) or package name (Google Play).
    var appIdentifier: String?

    init(
        screen: String,
        store: String? = nil,
        accountName: String? = nil,
        appName: String? = nil,
        appIdentifier: String? = nil
    ) {
        self.screen = screen
        self.store = store
        self.accountName = accountName
        self.appName = appName
        self.appIdentifier = appIdentifier
    }

    /// Context of a screen of `account`: only its display name and its store
    /// are taken from it.
    init(screen: String, account: AccountModel, appName: String? = nil, appIdentifier: String? = nil) {
        self.init(
            screen: screen,
            store: account.providerType.displayName,
            accountName: account.name,
            appName: appName,
            appIdentifier: appIdentifier
        )
    }

    /// Context of a screen of a Google Play `app` of `account`.
    init(screen: String, account: AccountModel, app: GooglePlayAppItem) {
        self.init(screen: screen, account: account, appName: app.displayName, appIdentifier: app.packageName)
    }
}

// MARK: - Report

/// Plain-text error report shared from an error screen through the system share
/// sheet (Copy, Mail, Messages, Slack, …).
///
/// Pure value type with no UIKit dependency: everything it prints comes from
/// the `ErrorReportContext`, the message and the `ErrorReportEnvironment`
/// passed in, so it is fully unit-testable and can never pick up secrets on its
/// own.
struct ErrorShareReport: Equatable, Sendable {

    /// The report body. The error message is kept verbatim on its own lines, so
    /// links in it stay intact (and tappable in the receiving app).
    let text: String

    /// Subject line for activities that support one (e.g. Mail).
    let subject: String

    // MARK: - Builder

    /// Builds the report.
    ///
    /// - Parameters:
    ///   - message: The error exactly as shown on screen. Never altered.
    ///   - context: Screen, store, account and app the error belongs to. Blank
    ///     optional values are left out of the report.
    ///   - environment: App version, OS, device and the report's timestamp.
    static func make(
        message: String,
        context: ErrorReportContext,
        environment: ErrorReportEnvironment
    ) -> ErrorShareReport {
        let screen = context.screen.trimmingCharacters(in: .whitespacesAndNewlines)

        var contextLines = [
            String(localized: "Screen: \(screen)", comment: "Error report line. Argument: the screen the error was shown on (e.g. Ratings & Reviews).")
        ]
        if let store = context.store.nonBlank {
            contextLines.append(String(localized: "Store: \(store)", comment: "Error report line. Argument: the store of the account (App Store Connect, Google Play, Firebase)."))
        }
        if let account = context.accountName.nonBlank {
            contextLines.append(String(localized: "Account: \(account)", comment: "Error report line. Argument: the account's display name."))
        }
        if let app = appDescription(name: context.appName.nonBlank, identifier: context.appIdentifier.nonBlank) {
            contextLines.append(String(localized: "App: \(app)", comment: "Error report line. Argument: the app's name and bundle id / package name, e.g. My App (com.example.app)."))
        }

        let version = "\(environment.appVersion) (\(environment.buildNumber))"
        let system = "\(environment.osName) \(environment.osVersion)"
        let date = formattedDate(environment.date, timeZone: environment.timeZone)
        let environmentLines = [
            String(localized: "App version: \(version)", comment: "Error report line. Argument: StackConnect's version and build, e.g. 1.4.0 (12)."),
            String(localized: "Operating system: \(system)", comment: "Error report line. Argument: the OS name and version, e.g. iOS 26.1."),
            String(localized: "Device: \(environment.deviceModel)", comment: "Error report line. Argument: the device model, e.g. iPhone (iPhone18,2)."),
            String(localized: "Date: \(date)", comment: "Error report line. Argument: when the report was made, as an ISO 8601 date with time zone.")
        ]

        let sections = [
            String(localized: "StackConnect — Error report", comment: "First line of the error report shared from an error screen."),
            contextLines.joined(separator: "\n"),
            String(localized: "Error message:", comment: "Error report heading, followed by the error message as shown on screen.") + "\n" + message,
            environmentLines.joined(separator: "\n")
        ]

        return ErrorShareReport(
            text: sections.joined(separator: "\n\n"),
            subject: String(
                localized: "StackConnect error: \(screen)",
                comment: "Subject line (e.g. for Mail) of a shared error report. Argument: the screen the error was shown on."
            )
        )
    }

    // MARK: - Private

    /// `"Name (identifier)"`, or whichever is known — once when both are equal
    /// (a Google Play app without a title is shown by its package name).
    private static func appDescription(name: String?, identifier: String?) -> String? {
        switch (name, identifier) {
        case let (name?, identifier?):
            return name == identifier ? name : "\(name) (\(identifier))"
        case let (name?, nil):
            return name
        case let (nil, identifier?):
            return identifier
        case (nil, nil):
            return nil
        }
    }

    /// ISO 8601 with the time zone offset, e.g. `2026-10-09T14:32:05-03:00`.
    private static func formattedDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == String {

    /// The trimmed value, or `nil` when the string is missing or blank.
    var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
