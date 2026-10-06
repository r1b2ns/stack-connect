import Foundation

/// Prefilled share content asking an App Store Connect team's Account Holder to
/// accept its pending agreements.
///
/// Only the Account Holder can accept Apple's agreements, but the person who sees
/// the "Action Required" banner is often an Admin or Developer. This value holds
/// everything the share sheet needs to route the request to the right person, and
/// it is the single place where that text lives.
///
/// Pure value type with no UIKit dependency, so it is fully unit-testable and can
/// be built from a ViewModel.
struct AgreementShareMessage: Equatable {

    /// Message body. Always ends with the agreements link. It never contains the
    /// recipient's own email address — that is only surfaced in `recipientTitle`.
    let text: String

    /// Subject line for activities that support one (e.g. Mail).
    let subject: String

    /// Who the message should be sent to, shown as the share sheet's header title:
    /// `"Name <email>"` when the Account Holder is known, or a generic
    /// "Account Holder of …" title otherwise.
    let recipientTitle: String

    /// The agreements console the recipient has to open.
    let url: URL

    // MARK: - Builders

    /// Builds the message from the raw Account Holder details.
    ///
    /// - Parameters:
    ///   - teamName: The App Store Connect team (account) name shown in the app.
    ///   - accountHolderName: The Account Holder's full name, or `nil` when unknown.
    ///     Blank values are treated as unknown.
    ///   - accountHolderEmail: The Account Holder's email, or `nil` when unknown.
    ///     Blank values are treated as unknown.
    ///   - url: The agreements link appended to the body.
    static func make(
        teamName: String,
        accountHolderName: String?,
        accountHolderEmail: String?,
        url: URL = AppStoreConnectLinks.agreements
    ) -> AgreementShareMessage {
        let name = accountHolderName.nonBlank
        let email = accountHolderEmail.nonBlank
        let link = url.absoluteString

        let text: String
        if let name {
            text = String(
                localized: "Hi \(name), the App Store Connect team \"\(teamName)\" has pending agreements. As Account Holder, please review and accept them: \(link)",
                comment: "Share message asking a named App Store Connect Account Holder to accept pending agreements. Arguments: Account Holder name, team name, agreements URL."
            )
        } else {
            text = String(
                localized: "Hi, the App Store Connect team \"\(teamName)\" has pending agreements that must be accepted by its Account Holder: \(link)",
                comment: "Fallback share message used when the Account Holder could not be determined. Arguments: team name, agreements URL."
            )
        }

        return AgreementShareMessage(
            text: text,
            subject: String(
                localized: "Action needed: App Store Connect agreements",
                comment: "Subject line (e.g. for Mail) of the message asking the Account Holder to accept pending agreements."
            ),
            recipientTitle: recipientTitle(teamName: teamName, name: name, email: email),
            url: url
        )
    }

    /// Builds the message from the Account Holder's `UserModel`, or the generic
    /// fallback when `accountHolder` is `nil`.
    ///
    /// Only the user's real first/last name is used for the greeting —
    /// `UserModel.displayName` is deliberately avoided because it falls back to the
    /// email, which must never end up in the message body.
    static func make(
        teamName: String,
        accountHolder: UserModel?,
        url: URL = AppStoreConnectLinks.agreements
    ) -> AgreementShareMessage {
        let fullName = [accountHolder?.firstName.nonBlank, accountHolder?.lastName.nonBlank]
            .compactMap { $0 }
            .joined(separator: " ")
        return make(
            teamName: teamName,
            accountHolderName: fullName,
            accountHolderEmail: accountHolder?.email,
            url: url
        )
    }

    // MARK: - Private

    private static func recipientTitle(teamName: String, name: String?, email: String?) -> String {
        switch (name, email) {
        case let (name?, email?):
            return "\(name) <\(email)>"
        case let (name?, nil):
            return name
        case let (nil, email?):
            return "\(String(localized: "Account Holder")) <\(email)>"
        case (nil, nil):
            return String(
                localized: "Account Holder of \"\(teamName)\"",
                comment: "Share sheet header title used when the Account Holder could not be determined. Argument: team name."
            )
        }
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
