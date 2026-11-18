import Foundation

/// A Google Play account's Keychain item (`credentials.<accountId>`): the
/// service-account JSON, or a "Sign in with Google" login (`source`).
struct GooglePlayCredentials: Codable, GoogleCredentialSourcing {
    /// The whole service-account key file; empty for a Google sign-in account.
    let serviceAccountJSON: String
    /// The Google login (`GoogleLoginGrant.loginId`); `nil` for a service account.
    let googleLoginId: String?

    init(serviceAccountJSON: String) {
        self.serviceAccountJSON = serviceAccountJSON
        self.googleLoginId = nil
    }

    init(googleLoginId: String) {
        self.serviceAccountJSON = ""
        self.googleLoginId = googleLoginId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let json = try container.decodeIfPresent(String.self, forKey: .serviceAccountJSON)
        let loginId = try container.decodeIfPresent(String.self, forKey: .googleLoginId)
        // One of the two must be there: another provider's item (e.g. App
        // Store Connect credentials) must not decode as this type.
        guard json != nil || loginId != nil else {
            throw DecodingError.keyNotFound(CodingKeys.serviceAccountJSON, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Neither serviceAccountJSON nor googleLoginId is present."
            ))
        }
        serviceAccountJSON = json ?? ""
        googleLoginId = loginId
    }

    private enum CodingKeys: String, CodingKey {
        case serviceAccountJSON, googleLoginId
    }
}
