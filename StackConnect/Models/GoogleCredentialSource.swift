import Foundation

/// How a Firebase or Google Play account authenticates.
///
/// - `serviceAccount`: the service-account JSON key file, kept whole in the
///   Keychain (unchanged storage format, plan D2 of the Play plan).
/// - `googleSignIn`: a "Sign in with Google" login (plan G5, G6). The account
///   only stores the login's ID; the refresh token lives in that login's own
///   Keychain item (`GoogleLoginKeychainStore`), shared by every account added
///   with the same Google user.
enum GoogleCredentialSource: Equatable, Sendable {
    case serviceAccount(json: String)
    case googleSignIn(loginId: String)

    var googleLoginId: String? {
        if case .googleSignIn(let loginId) = self { return loginId }
        return nil
    }
}

/// The Keychain shape shared by `GooglePlayCredentials` and `FirebaseCredentials`:
/// `serviceAccountJSON` (as before) or, for Google sign-in, `googleLoginId`.
/// Items written before Google sign-in existed decode unchanged.
protocol GoogleCredentialSourcing {
    var serviceAccountJSON: String { get }
    var googleLoginId: String? { get }
}

extension GoogleCredentialSourcing {
    /// A non-empty `googleLoginId` wins: such items carry no JSON.
    var source: GoogleCredentialSource {
        if let googleLoginId, !googleLoginId.isEmpty {
            return .googleSignIn(loginId: googleLoginId)
        }
        return .serviceAccount(json: serviceAccountJSON)
    }

    var isGoogleSignIn: Bool { source.googleLoginId != nil }
}
