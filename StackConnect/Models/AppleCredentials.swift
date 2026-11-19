import Foundation

/// An App Store Connect account's Keychain item (`credentials.<accountId>`):
/// the API key (`.p8`, Key ID, Issuer ID), or, for an account added with
/// "Sign in with Apple ID", a reference to the Apple ID's web session
/// (`webSession`, plan `apple-id-sign-in.md` D3/D4).
///
/// The session itself is not in this item: every team account of one Apple ID
/// shares the Keychain item `appleSession.{appleId}` (`AppleSessionKeychainStore`),
/// so signing in again replaces it once for all of them. Items written before
/// the Apple ID sign-in existed decode unchanged (`webSession == nil`).
struct AppleCredentials: Codable {
    /// Empty for a web session account.
    let issuerID: String
    /// Empty for a web session account.
    let privateKeyID: String
    /// Empty for a web session account.
    let privateKey: String
    /// The Apple ID session this account uses; `nil` for an API key.
    let webSession: AppleWebSessionReference?

    init(issuerID: String, privateKeyID: String, privateKey: String) {
        self.issuerID = issuerID
        self.privateKeyID = privateKeyID
        self.privateKey = privateKey
        self.webSession = nil
    }

    init(webSession: AppleWebSessionReference) {
        self.issuerID = ""
        self.privateKeyID = ""
        self.privateKey = ""
        self.webSession = webSession
    }

    /// How the account authenticates.
    var source: AppleCredentialSource {
        if let webSession { return .webSession(webSession) }
        return .apiKey
    }

    var isWebSession: Bool { webSession != nil }
}

/// How an App Store Connect account authenticates.
enum AppleCredentialSource: Equatable, Sendable {
    /// The App Store Connect API key in the same Keychain item.
    case apiKey
    /// "Sign in with Apple ID": the shared session of `reference.appleId`,
    /// acting for the team `reference.teamId`.
    case webSession(AppleWebSessionReference)
}

/// Which Apple ID session, and which of its teams, a session account uses.
/// Not secret: the session blob stays in its own Keychain item.
struct AppleWebSessionReference: Codable, Hashable, Sendable {
    /// The Apple ID e-mail, normalized (`AppleSessionKeychainStore.normalized`).
    let appleId: String
    /// The App Store Connect team (`AppleTeam.providerId`).
    let teamId: UInt64
    /// The team's display name when the account was added.
    let teamName: String

    init(appleId: String, teamId: UInt64, teamName: String) {
        self.appleId = AppleSessionKeychainStore.normalized(appleId)
        self.teamId = teamId
        self.teamName = teamName
    }
}
