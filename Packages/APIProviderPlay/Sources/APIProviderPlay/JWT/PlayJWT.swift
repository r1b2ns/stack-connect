import Foundation
import Security

// MARK: - Google JWT Header

struct GoogleJWTHeader: Encodable {
    let alg = "RS256"
    let typ = "JWT"
    let kid: String
}

// MARK: - Google JWT Claims

struct GoogleJWTClaims: Encodable {
    let iss: String
    let scope: String
    let aud: String
    let iat: Int
    let exp: Int
}

// MARK: - Play JWT

struct PlayJWT {

    let configuration: PlayConfiguration

    func signedAssertion() throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let header = GoogleJWTHeader(kid: configuration.serviceAccount.privateKeyId)
        let claims = GoogleJWTClaims(
            iss: configuration.serviceAccount.clientEmail,
            scope: configuration.scopes.joined(separator: " "),
            aud: configuration.serviceAccount.tokenUri,
            iat: now,
            exp: now + Int(configuration.expirationDuration)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let headerBase64 = try encoder.encode(header).base64URLEncoded()
        let claimsBase64 = try encoder.encode(claims).base64URLEncoded()
        let signingInput = "\(headerBase64).\(claimsBase64)"

        guard let inputData = signingInput.data(using: .utf8) else {
            throw PlayAuthError.invalidJWTPayload
        }

        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            configuration.privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            inputData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw PlayAuthError.signingFailed(error as Swift.Error)
            }
            throw PlayAuthError.signingFailed(nil)
        }

        let signatureBase64 = signatureData.base64URLEncoded()
        return "\(signingInput).\(signatureBase64)"
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}
